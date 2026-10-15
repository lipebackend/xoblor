-- Assaltos à carteira. Toda a lógica roda no servidor; o banco (Extra.Bank) nunca é roubado.
-- Estado salvo em Extra.Robbery = { RobCooldownUntil, ProtectedUntil, WantedUntil } (os.time()).
local Players = game:GetService("Players")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local JobService = require(script.Parent.JobService)
local RemoteUtil = require(script.Parent.RemoteUtil)
local Logic = require(script.Parent.RobberyLogic)

local RobberyService = {}
local MAX_DISTANCE = Logic.MAX_DISTANCE
local POLICE_TEAM = "Polícia"
local POLICE_JOB = "policial"

local robbedEvent = RemoteUtil.Get("Robbed", "RemoteEvent")
local resultEvent = RemoteUtil.Get("RobberyResult", "RemoteEvent")
local stateEvent = RemoteUtil.Get("RobberyState", "RemoteEvent")
local busy = {}

local function stateOf(player)
	if not Economy.IsLoaded(player) then
		return nil
	end
	local extra = Data.GetExtra(player)
	if not extra then
		return nil
	end
	local s = Logic.NormalizeState(extra.Robbery)
	extra.Robbery = s
	return s
end

function RobberyService.GetState(player)
	local s = stateOf(player)
	if not s then
		return nil
	end
	local now = os.time()
	return {
		RobCooldownUntil = s.RobCooldownUntil,
		ProtectedUntil = s.ProtectedUntil,
		Wanted = s.WantedUntil > now,
		WantedUntil = s.WantedUntil,
	}
end

function RobberyService.IsWanted(player)
	local s = stateOf(player)
	return s ~= nil and s.WantedUntil > os.time()
end

local function notify(player)
	local state = RobberyService.GetState(player)
	if state then
		stateEvent:FireClient(player, state)
	end
end

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function isPolice(player)
	return JobService.GetJob(player) == POLICE_JOB or (player.Team ~= nil and player.Team.Name == POLICE_TEAM)
end

function RobberyService.Rob(robber, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == robber then
		return false, "Invalid"
	end
	if target.Parent ~= Players then
		return false, "TargetGone" -- saiu do servidor: não é exploit, não gera strike
	end
	local rs, ts = stateOf(robber), stateOf(target)
	if not rs or not ts then
		return false, "NotLoaded"
	end
	local now = os.time()
	local denied = Logic.Check(rs, ts, now, isPolice(robber))
	if denied then
		return false, denied
	end
	local a, b = rootOf(robber), rootOf(target)
	if not a or not b or (a.Position - b.Position).Magnitude > MAX_DISTANCE then
		return false, "TooFar"
	end
	local ok, wallet = Economy.GetBalance(target)
	if not ok then
		return false, "NotLoaded"
	end
	local amount = Logic.Amount(wallet, math.random(Logic.MIN_PCT, Logic.MAX_PCT))
	if amount < 1 then
		return false, "TargetEmpty"
	end
	local spent, err = Economy.SpendCoins(target, amount, "robbery")
	if not spent then
		return false, err == "InsufficientFunds" and "TargetEmpty" or err
	end
	local added, addErr = Economy.AddCoins(robber, amount, "robbery")
	if not added then
		Economy.AddCoins(target, amount, "robbery:refund")
		return false, addErr
	end
	Logic.ApplySuccess(rs, ts, now)
	warn(("[Robbery] %d roubou %d de %d"):format(robber.UserId, amount, target.UserId))
	robbedEvent:FireClient(target, robber.UserId, amount)
	notify(robber)
	notify(target)
	return true, amount
end

-- RobAttempt: 1 chamada a cada 0,5s. Payload inválido gera Flag (via BindFunction).
RemoteUtil.BindFunction("RobAttempt", 0.5, 1, function(player, targetUserId)
	if not RemoteUtil.IsInt(targetUserId, 1) then
		return false, "Invalid"
	end
	if targetUserId == player.UserId then
		return false, "Invalid"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		-- alvo saiu entre o clique e a chamada: resposta normal, sem Flag
		resultEvent:FireClient(player, false, "TargetGone", targetUserId)
		return false, "TargetGone"
	end
	if busy[player] then
		return false, "RateLimited"
	end
	busy[player] = true
	local ran, ok, res = pcall(RobberyService.Rob, player, target)
	busy[player] = nil
	if not ran then
		warn(("[Robbery] Rob falhou para %d: %s"):format(player.UserId, tostring(ok)))
		ok, res = false, "ServerError"
	end
	resultEvent:FireClient(player, ok, res, targetUserId)
	return ok, res
end)

-- estado inicial ao carregar (e jogadores já no servidor)
Economy.BalanceChanged:Connect(function(player, _, reason)
	if reason == "load" then
		notify(player)
	end
end)
for _, p in Players:GetPlayers() do
	if Economy.IsLoaded(p) then
		task.spawn(notify, p)
	end
end

-- avisa quando o "procurado" expira
task.spawn(function()
	local wasWanted = {}
	while true do
		task.wait(5)
		for _, p in Players:GetPlayers() do
			local w = RobberyService.IsWanted(p)
			if wasWanted[p] and not w then
				notify(p)
			end
			wasWanted[p] = w or nil
		end
		for p in pairs(wasWanted) do
			if p.Parent ~= Players then
				wasWanted[p] = nil
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	busy[p] = nil
end)

return RobberyService
