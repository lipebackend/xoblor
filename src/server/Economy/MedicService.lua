-- Desmaio e atendimento médico. Fome OU energia em 0 por FAINT_AFTER segundos desmaia o jogador;
-- um médico (time Saúde) reanima com o prompt "Reanimar", ou depois de BLEEDOUT ele vai ao hospital.
-- Regras e padrões em MedicLogic.Config. O desmaio não é salvo (DownState fica só em memória).
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(script.Parent.EconomyService)
local RemoteUtil = require(script.Parent.RemoteUtil)
local Guard = require(script.Parent.RemoteGuard)
local NeedsService = require(script.Parent.NeedsService)
local JobService = require(script.Parent.JobService)
local JailState = require(script.Parent.JailState)
local DownState = require(script.Parent.DownState)
local MedicLogic = require(script.Parent.MedicLogic)
local JobCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("JobCatalog"))

local MedicService = {}
local Config = MedicLogic.Config
local MEDIC_JOB = JobCatalog.MEDIC_JOB
local MEDIC_TEAM = JobCatalog.Get(MEDIC_JOB).Team

local medicEvent = RemoteUtil.Get("MedicEvent", "RemoteEvent") -- (kind, info)
local zeroSince = {} -- [player] = os.clock() desde que a necessidade zerou
local reviveCooldown = {} -- [player] = os.clock()
local savedSpeed = {} -- [player] = { Walk, Jump, JumpH } antes do desmaio

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function humanoidOf(player)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function isMedic(player)
	return JobService.GetJob(player) == MEDIC_JOB or (player.Team ~= nil and player.Team.Name == MEDIC_TEAM)
end

local function hospitalSpot()
	for _, p in CollectionService:GetTagged("HospitalSpawn") do
		if p:IsA("BasePart") and p:IsDescendantOf(workspace) then
			return p
		end
	end
	warn("[Medic] nenhuma parte com tag HospitalSpawn")
	return nil
end

local function publishTimer(player)
	local d = DownState.Get(player)
	player:SetAttribute("DownedLeft", d and math.ceil(MedicLogic.BleedoutLeft(d.At, os.clock())) or nil)
end

function MedicService.Faint(player)
	if DownState.IsDowned(player) then
		return
	end
	DownState.Set(player, { At = os.clock() })
	zeroSince[player] = nil
	local hum = humanoidOf(player)
	if hum then
		savedSpeed[player] = { Walk = hum.WalkSpeed, Jump = hum.JumpPower, JumpH = hum.JumpHeight }
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum.PlatformStand = true
	end
	publishTimer(player)
	medicEvent:FireClient(player, "fainted", { Bleedout = Config.BLEEDOUT })
end

-- Acorda: devolve movimento (antes das necessidades, para o NeedsService ajustar a velocidade depois).
local function wake(player, restore)
	DownState.Set(player, nil)
	local hum = humanoidOf(player)
	if hum then
		hum.PlatformStand = false
		local saved = savedSpeed[player]
		if saved then
			if hum.WalkSpeed == 0 then
				hum.WalkSpeed = saved.Walk
			end
			hum.JumpPower, hum.JumpHeight = saved.Jump, saved.JumpH
		end
	end
	savedSpeed[player] = nil
	zeroSince[player] = nil
	publishTimer(player)
	if restore then
		local ok, hunger, energy = NeedsService.GetNeeds(player)
		if ok then
			local dh, de = MedicLogic.RestoreDelta(hunger), MedicLogic.RestoreDelta(energy)
			if dh > 0 then
				NeedsService.AddHunger(player, dh)
			end
			if de > 0 then
				NeedsService.AddEnergy(player, de)
			end
		end
	end
end

-- Ida ao hospital: cobra HOSPITAL_FEE (limitada à carteira, vai para a "casa"), teleporta e acorda.
function MedicService.Hospital(player)
	local _, wallet = Economy.GetBalance(player)
	local fee = MedicLogic.Fee(Config.HOSPITAL_FEE, wallet)
	if fee > 0 and not Economy.SpendCoins(player, fee, "medic:hospital") then
		fee = 0
	end
	wake(player, true)
	local spot = hospitalSpot()
	if spot and player.Character then
		player.Character:PivotTo(spot.CFrame + Vector3.new(0, 4, 0))
	end
	warn(("[Medic] %d foi ao hospital, taxa %d"):format(player.UserId, fee))
	medicEvent:FireClient(player, "hospital", { Fee = fee })
end

function MedicService.Revive(medic, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == medic then
		return false, "Invalid"
	end
	if not (Economy.IsLoaded(medic) and Economy.IsLoaded(target)) then
		return false, "NotLoaded"
	end
	local a, b = rootOf(medic), rootOf(target)
	local now = os.clock()
	local err = MedicLogic.CanRevive({
		IsMedic = isMedic(medic),
		MedicDowned = DownState.IsDowned(medic),
		MedicJailed = JailState.IsJailed(medic),
		CooldownUntil = reviveCooldown[medic] or 0,
		TargetDowned = DownState.IsDowned(target),
		Distance = select(2, Guard.Within(a and a.Position, b and b.Position, math.huge)),
		Now = now,
	})
	if err then
		return false, err
	end
	reviveCooldown[medic] = now + Config.REVIVE_COOLDOWN
	local _, wallet = Economy.GetBalance(target)
	local fee = MedicLogic.Fee(Config.REVIVE_FEE, wallet)
	if fee > 0 and not Economy.Transfer(target, medic, fee) then
		fee = 0
	end
	wake(target, true)
	warn(("[Medic] %d reanimou %d, taxa %d"):format(medic.UserId, target.UserId, fee))
	medicEvent:FireClient(target, "revived", { By = medic.UserId, Fee = fee })
	medicEvent:FireClient(medic, "reviver", { Target = target.UserId, Fee = fee })
	return true, fee
end

RemoteUtil.BindFunction("Revive", function(medic, targetUserId)
	if not RemoteUtil.IsInt(targetUserId, 1) or targetUserId == medic.UserId then
		return false, "Invalid"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return false, "TargetGone"
	end
	return MedicService.Revive(medic, target)
end)

-- "Chamar médico": avisa os médicos em serviço com a posição. Limite: 1 a cada CALL_INTERVAL.
RemoteUtil.BindFunction("CallMedic", function(player)
	if not DownState.IsDowned(player) then
		return false, "NotDowned"
	end
	local root = rootOf(player)
	if not root then
		return false, "NoCharacter"
	end
	local n = 0
	for _, p in Players:GetPlayers() do
		if p ~= player and isMedic(p) then
			medicEvent:FireClient(p, "call", { From = player.UserId, Position = root.Position })
			n += 1
		end
	end
	return true, n
end, { interval = Config.CALL_INTERVAL, burst = 1 })

-- reset desmaiado = ida ao hospital (cobra a taxa no novo personagem)
local function hookCharacter(player)
	player.CharacterAdded:Connect(function(char)
		if DownState.IsDowned(player) then
			char:WaitForChild("HumanoidRootPart", 5)
			task.defer(MedicService.Hospital, player)
		end
	end)
end
Players.PlayerAdded:Connect(hookCharacter)
for _, p in Players:GetPlayers() do
	hookCharacter(p)
end

-- loop: conta o tempo com necessidade zerada, desmaia, sangramento até o hospital
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for _, p in Players:GetPlayers() do
			if Economy.IsLoaded(p) then
				local downed, jailed = DownState.Get(p), JailState.IsJailed(p)
				if downed then
					if jailed then
						wake(p, false) -- preso não fica desmaiado (sem taxa)
					elseif MedicLogic.BleedoutLeft(downed.At, now) <= 0 then
						MedicService.Hospital(p)
					else
						publishTimer(p)
					end
				else
					local ok, hunger, energy = NeedsService.GetNeeds(p)
					local faint
					zeroSince[p], faint =
						MedicLogic.FaintStep(zeroSince[p], ok and (hunger <= 0 or energy <= 0), jailed, false, now)
					if faint then
						MedicService.Faint(p)
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	zeroSince[p], reviveCooldown[p], savedSpeed[p] = nil, nil, nil
end)

return MedicService
