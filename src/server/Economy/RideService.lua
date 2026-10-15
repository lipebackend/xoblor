-- Corridas de mototaxi: o servidor sorteia um destino (partes com tag RideDropoff),
-- confere a chegada e paga via JobService.PayRide. Regras puras em RideLogic.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Economy = require(script.Parent.EconomyService)
local JobService = require(script.Parent.JobService)
local RemoteUtil = require(script.Parent.RemoteUtil)
local RideLogic = require(script.Parent.RideLogic)

local RideService = {}
local JOB_ID = "mototaxi"
local CHECK_INTERVAL = 0.5

local stateEvent = RemoteUtil.Get("RideState", "RemoteEvent")
local rides = {} -- [player] = ride (RideLogic.NewRide + Part)
local cooldownUntil = {} -- [player] = os.clock()

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function dropoffs()
	local out = {}
	for _, p in CollectionService:GetTagged("RideDropoff") do
		if p:IsA("BasePart") and p:IsDescendantOf(workspace) then
			table.insert(out, p)
		end
	end
	return out
end

-- Avisa o cliente. status: "Started" | "Arrived" | "Cancelled" | "Expired" | "TooFast"
local function send(player, status, amount)
	local ride = rides[player]
	stateEvent:FireClient(player, {
		Status = status,
		Active = ride ~= nil,
		Target = ride and ride.Part or nil,
		Name = ride and ride.Part.Name or nil,
		Amount = amount,
		CooldownLeft = math.max(0, (cooldownUntil[player] or 0) - os.clock()),
	})
end

local function finish(player, status, amount)
	if not rides[player] then
		return
	end
	rides[player] = nil
	cooldownUntil[player] = os.clock() + RideLogic.COOLDOWN
	if player.Parent == Players then
		send(player, status, amount)
	end
end

function RideService.Cancel(player)
	finish(player, "Cancelled")
end

function RideService.GetRide(player)
	return rides[player]
end

function RideService.Start(player)
	local now = os.clock()
	local err = RideLogic.CanStart(JobService.GetJob(player) == JOB_ID, rides[player], cooldownUntil[player], now)
	if err then
		return false, err
	end
	local root = rootOf(player)
	if not root then
		return false, "NoCharacter"
	end
	local points = dropoffs()
	local distances = {}
	for i, p in points do
		distances[i] = (p.Position - root.Position).Magnitude
	end
	local i = RideLogic.PickDropoff(distances, math.random)
	if not i then
		return false, "NoDropoff"
	end
	local ride = RideLogic.NewRide(i, distances[i], now)
	ride.Part = points[i]
	RideLogic.Sample(ride, root.Position, now)
	rides[player] = ride
	send(player, "Started")
	return true, ride.Part.Name
end

local function tick(player, ride)
	if ride.Paying then
		return
	end
	local now = os.clock()
	if not ride.Part:IsDescendantOf(workspace) then
		finish(player, "Cancelled") -- destino sumiu do mapa
		return
	end
	if JobService.GetJob(player) ~= JOB_ID then
		finish(player, "Cancelled")
		return
	end
	local root = rootOf(player)
	RideLogic.Sample(ride, root and root.Position or nil, now)
	local dist = root and (ride.Part.Position - root.Position).Magnitude or nil
	local status = RideLogic.Check(ride, dist, now)
	if status == "Expired" then
		finish(player, "Expired")
	elseif status == "TooFast" then
		-- chegou antes do tempo mínimo (teleporte/exploit): anula a corrida sem pagar
		warn(("[Ride] %d chegou rápido demais (%.1fs)"):format(player.UserId, now - ride.StartedAt))
		RemoteUtil.Flag(player, "Ride: chegada rápida demais")
		finish(player, "TooFast")
	elseif status == "ShortPath" then
		-- chegou sem percorrer o caminho (teleporte e espera): anula sem pagar
		warn(
			("[Ride] %d percurso curto (%.0f de %.0f studs, %d saltos)"):format(
				player.UserId,
				ride.Path or 0,
				ride.Distance or 0,
				ride.Jumps or 0
			)
		)
		RemoteUtil.Flag(player, "Ride: percurso curto")
		finish(player, "TooFast")
	elseif status == "Arrived" then
		ride.Paying = true -- PayRide pode ceder (checagem de VIP); evita pagar duas vezes
		local _, before = Economy.GetBalance(player)
		local ok, res = JobService.PayRide(player)
		if rides[player] ~= ride then
			return -- cancelada enquanto pagava (saiu do servidor)
		end
		if ok then
			finish(player, "Arrived", type(before) == "number" and res - before or nil)
		else
			warn(("[Ride] pagamento falhou para %d: %s"):format(player.UserId, tostring(res)))
			finish(player, "Cancelled")
		end
	end
end

RemoteUtil.BindFunction("RideStart", 1, 1, function(player)
	return RideService.Start(player)
end)

RemoteUtil.BindFunction("RideCancel", 1, 1, function(player)
	if not rides[player] then
		return false, "NoRide"
	end
	RideService.Cancel(player)
	return true
end)

-- largou o emprego no meio: cancela na hora
JobService.JobChanged:Connect(function(player, jobId)
	if jobId ~= JOB_ID then
		RideService.Cancel(player)
	end
end)

-- morrer/renascer não cancela: a corrida segue até chegar ou expirar

Players.PlayerRemoving:Connect(function(p)
	rides[p] = nil
	cooldownUntil[p] = nil
end)

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		for p, ride in pairs(rides) do
			if p.Parent ~= Players then
				rides[p] = nil
			else
				task.spawn(tick, p, ride)
			end
		end
	end
end)

return RideService
