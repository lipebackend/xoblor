-- Prisão: policial prende procurado (prompt "Prender" no cliente, tudo validado aqui).
-- Pena e multa em ArrestLogic.Config. A pena fica no campo Jail = { Remaining, Reason } do perfil
-- e só corre com o jogador no servidor: quem sai e volta cumpre o que faltava.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Economy = require(script.Parent.EconomyService)
local RemoteUtil = require(script.Parent.RemoteUtil)
local RobberyService = require(script.Parent.RobberyService)
local JailState = require(script.Parent.JailState)
local ArrestLogic = require(script.Parent.ArrestLogic)

local ArrestService = {}
local Config = ArrestLogic.Config
local arrestedEvent = RemoteUtil.Get("Arrested", "RemoteEvent") -- (role "cop"|"prisoner", info)
local copCooldown = {} -- [player] = os.clock()

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function spot(tag)
	for _, p in CollectionService:GetTagged(tag) do
		if p:IsA("BasePart") and p:IsDescendantOf(workspace) then
			return p
		end
	end
	return nil
end

local function teleport(player, tag)
	local root, part = rootOf(player), spot(tag)
	if root and part then
		player.Character:PivotTo(part.CFrame + Vector3.new(0, 4, 0))
		return true
	end
	if not part then
		warn("[Arrest] nenhuma parte com tag " .. tag)
	end
	return false
end

function ArrestService.Arrest(cop, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == cop then
		return false, "Invalid"
	end
	if not (Economy.IsLoaded(cop) and Economy.IsLoaded(target)) then
		return false, "NotLoaded"
	end
	local a, b = rootOf(cop), rootOf(target)
	local now = os.clock()
	local err = ArrestLogic.CanArrest({
		CopIsPolice = RobberyService.IsPolice(cop),
		CopJailed = JailState.IsJailed(cop),
		CopCooldownUntil = copCooldown[cop] or 0,
		TargetIsPolice = RobberyService.IsPolice(target),
		TargetWanted = RobberyService.IsWanted(target),
		TargetJailed = JailState.IsJailed(target),
		Distance = (a and b) and (a.Position - b.Position).Magnitude or nil,
		Now = now,
	})
	if err then
		return false, err
	end
	copCooldown[cop] = now + Config.ARREST_COOLDOWN

	local loot, victims = RobberyService.ClearWanted(target)
	local sentence = ArrestLogic.Sentence(loot)

	-- multa: % da carteira do preso vai para o policial (o banco nunca é tocado)
	local _, wallet = Economy.GetBalance(target)
	local fine = ArrestLogic.Fine(wallet)
	if fine > 0 and not Economy.Transfer(target, cop, fine) then
		fine = 0
	end

	-- devolução às vítimas (Config.VICTIM_REFUND), só para quem está online
	local refunded = 0
	local _, left = Economy.GetBalance(target)
	local plan = ArrestLogic.RefundPlan(victims, left)
	for _, r in plan do
		local victim = Players:GetPlayerByUserId(r.u)
		if victim and Economy.IsLoaded(victim) and Economy.SpendCoins(target, r.v, "arrest:refund") then
			if Economy.AddCoins(victim, r.v, "robbery:refund") then
				refunded += r.v
			else
				Economy.AddCoins(target, r.v, "arrest:refund_undo")
			end
		end
	end

	JailState.Jail(target, sentence, "assalto")
	teleport(target, "Jail")
	warn(("[Arrest] %d prendeu %d: %ds, multa %d, devolvido %d"):format(cop.UserId, target.UserId, sentence, fine, refunded))
	arrestedEvent:FireClient(target, "prisoner", { By = cop.UserId, Sentence = sentence, Fine = fine, Refunded = refunded })
	arrestedEvent:FireClient(cop, "cop", { Target = target.UserId, Sentence = sentence, Fine = fine })
	return true, sentence
end

RemoteUtil.BindFunction("Arrest", 0.5, 1, function(cop, targetUserId)
	if not RemoteUtil.IsInt(targetUserId, 1) or targetUserId == cop.UserId then
		return false, "Invalid"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return false, "TargetGone"
	end
	return ArrestService.Arrest(cop, target)
end)

local function release(player)
	JailState.Release(player)
	teleport(player, "JailRelease")
	arrestedEvent:FireClient(player, "released", {})
end

-- carregou o perfil: restaura atributo e manda de volta para a cadeia
Economy.BalanceChanged:Connect(function(player, _, reason)
	if reason == "load" then
		JailState.Publish(player)
		if JailState.IsJailed(player) then
			teleport(player, "Jail")
		end
		RobberyService.Notify(player) -- atributo Wanted
	end
end)

-- renasceu preso: volta para a cadeia
local function hookCharacter(player)
	player.CharacterAdded:Connect(function(char)
		if JailState.IsJailed(player) then
			char:WaitForChild("HumanoidRootPart", 5)
			task.defer(teleport, player, "Jail")
		end
	end)
end
Players.PlayerAdded:Connect(hookCharacter)
for _, p in Players:GetPlayers() do
	hookCharacter(p)
end

-- relógio da pena (só online), soltura e "cerca" da cadeia
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(1)
		local now = os.clock()
		local dt = now - last
		last = now
		for _, p in Players:GetPlayers() do
			if Economy.IsLoaded(p) and JailState.IsJailed(p) then
				if JailState.Tick(p, dt) then
					release(p)
				else
					local root, jail = rootOf(p), spot("Jail")
					if root and jail and (root.Position - jail.Position).Magnitude > Config.JAIL_RADIUS then
						teleport(p, "Jail")
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	copCooldown[p] = nil
end)

return ArrestService
