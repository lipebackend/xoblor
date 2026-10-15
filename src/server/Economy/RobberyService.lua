-- Assaltos à carteira. Toda a lógica roda no servidor; o banco (Extra.Bank) nunca é roubado.
-- Estado salvo em Extra.Robbery = { RobCooldownUntil, ProtectedUntil, WantedUntil } (os.time()).
local Players = game:GetService("Players")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local JobService = require(script.Parent.JobService)
local RemoteUtil = require(script.Parent.RemoteUtil)
local JailState = require(script.Parent.JailState)
local DownState = require(script.Parent.DownState)
local MedicLogic = require(script.Parent.MedicLogic)

local RobberyService = {}
local MAX_DISTANCE = 8
local ROB_COOLDOWN = 300
local PROTECTION = 180
local WANTED_TIME = 120
local MIN_PCT, MAX_PCT = 10, 30
local MAX_ROB = 2000
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
	local s = type(extra.Robbery) == "table" and extra.Robbery or {}
	s.RobCooldownUntil = tonumber(s.RobCooldownUntil) or 0
	s.ProtectedUntil = tonumber(s.ProtectedUntil) or 0
	s.WantedUntil = tonumber(s.WantedUntil) or 0
	s.Loot = tonumber(s.Loot) or 0 -- roubado desde que ficou procurado (pena/devolução)
	s.Victims = type(s.Victims) == "table" and s.Victims or {}
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
		-- atributo replicado: todos os clientes veem quem está procurado (placa e prompt da polícia)
		player:SetAttribute("Wanted", state.Wanted or nil)
		stateEvent:FireClient(player, state)
	end
end
RobberyService.Notify = notify

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
	if isPolice(robber) then
		return false, "SameTeamPolice"
	end
	local blocked = JailState.Block(robber, "Rob")
	if blocked then
		return false, blocked
	end
	if not MedicLogic.CanBeRobbed(DownState.IsDowned(target)) then
		return false, "TargetDowned"
	end
	if JailState.IsJailed(target) then
		return false, "TargetJailed"
	end
	local now = os.time()
	if rs.RobCooldownUntil > now then
		return false, "Cooldown"
	end
	if ts.ProtectedUntil > now then
		return false, "TargetProtected"
	end
	local a, b = rootOf(robber), rootOf(target)
	if not a or not b or (a.Position - b.Position).Magnitude > MAX_DISTANCE then
		return false, "TooFar"
	end
	local ok, wallet = Economy.GetBalance(target)
	if not ok then
		return false, "NotLoaded"
	end
	local amount = math.min(math.floor(wallet * math.random(MIN_PCT, MAX_PCT) / 100), MAX_ROB)
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
	if rs.WantedUntil <= now then
		rs.Loot, rs.Victims = 0, {} -- nova "ficha" a cada período de procurado
	end
	rs.Loot += amount
	table.insert(rs.Victims, { u = target.UserId, v = amount })
	rs.RobCooldownUntil = now + ROB_COOLDOWN
	rs.WantedUntil = now + WANTED_TIME
	ts.ProtectedUntil = now + PROTECTION
	warn(("[Robbery] %d roubou %d de %d"):format(robber.UserId, amount, target.UserId))
	robbedEvent:FireClient(target, robber.UserId, amount)
	notify(robber)
	notify(target)
	return true, amount
end

RobberyService.IsPolice = isPolice

-- Prisão: encerra o "procurado" e devolve o roubado no período e as vítimas.
function RobberyService.ClearWanted(player)
	local s = stateOf(player)
	if not s then
		return 0, {}
	end
	local loot, victims = s.Loot, s.Victims
	s.WantedUntil, s.Loot, s.Victims = 0, 0, {}
	notify(player)
	return loot, victims
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
