-- NeedsService: fome e energia (0-100), salvas em DataStoreHandler.GetExtra(player).Hunger/.Energy.
-- Só o servidor altera. O cliente recebe Remotes.NeedsChanged(hunger, energy).
local Players = game:GetService("Players")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local RemoteUtil = require(script.Parent.RemoteUtil)

local MAX_NEED = 100
local HUNGER_DECAY_INTERVAL = 30 -- segundos para perder 1 de fome
local ENERGY_DECAY_INTERVAL = 45 -- segundos para perder 1 de energia
local DEFAULT_WALKSPEED = 16 -- usado se não houver atributo BaseWalkSpeed (Humanoid, depois Player)
local EXHAUSTED_FACTOR = 0.6 -- fração da velocidade base com fome ou energia em 0

local NeedsService = {}
local needsChanged = RemoteUtil.Get("NeedsChanged", "RemoteEvent")
local announced = {} -- [player] = true depois do primeiro envio

local function clamp(n)
	n = tonumber(n)
	if n == nil or n ~= n then
		return MAX_NEED
	end
	return math.clamp(math.floor(n), 0, MAX_NEED)
end

local function validDelta(n)
	return type(n) == "number" and n == n and n % 1 == 0 and math.abs(n) <= 1e6
end

local penalized = {} -- [player] = WalkSpeed que nós aplicamos

local function baseSpeed(player, hum)
	local v = hum:GetAttribute("BaseWalkSpeed")
	if type(v) ~= "number" then
		v = player:GetAttribute("BaseWalkSpeed")
	end
	if type(v) ~= "number" or v ~= v or v <= 0 then
		v = DEFAULT_WALKSPEED
	end
	return v
end

local function applyEffect(player, extra)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local exhausted = extra.Hunger <= 0 or extra.Energy <= 0
	local base = baseSpeed(player, hum)
	if exhausted then
		local slow = base * EXHAUSTED_FACTOR
		-- só reduz; não sobrescreve quem já deixou o jogador mais lento
		if hum.WalkSpeed > slow then
			hum.WalkSpeed = slow
			penalized[player] = slow
		end
	elseif penalized[player] then
		-- só restaura se ninguém mexeu na velocidade depois de nós
		if math.abs(hum.WalkSpeed - penalized[player]) < 0.01 then -- WalkSpeed é float32
			hum.WalkSpeed = base
		end
		penalized[player] = nil
	end
end

-- Normaliza o Extra (default 100) e devolve a tabela, ou nil se o perfil não carregou.
local function getExtra(player)
	if not Economy.IsLoaded(player) then
		return nil
	end
	local extra = Data.GetExtra(player)
	if not extra then
		return nil
	end
	extra.Hunger = clamp(extra.Hunger)
	extra.Energy = clamp(extra.Energy)
	return extra
end

local function notify(player, extra)
	needsChanged:FireClient(player, extra.Hunger, extra.Energy)
	applyEffect(player, extra)
end

-- Retorna ok, hunger, energy; ou false, "NotLoaded" se o perfil ainda não carregou.
function NeedsService.GetNeeds(player)
	local extra = getExtra(player)
	if not extra then
		return false, "NotLoaded"
	end
	return true, extra.Hunger, extra.Energy
end

local function add(field, player, n)
	if not validDelta(n) then
		return false, "InvalidAmount"
	end
	local extra = getExtra(player)
	if not extra then
		return false, "NotLoaded"
	end
	local value = math.clamp(extra[field] + n, 0, MAX_NEED)
	if value ~= extra[field] then
		extra[field] = value
		notify(player, extra)
	end
	return true, value
end

function NeedsService.AddHunger(player, n)
	return add("Hunger", player, n)
end

function NeedsService.AddEnergy(player, n)
	return add("Energy", player, n)
end

-- Envio inicial quando o perfil carregar.
local function watch(player)
	task.spawn(function()
		while player.Parent and not Economy.IsLoaded(player) do
			task.wait(0.5)
		end
		local extra = getExtra(player)
		if extra then
			announced[player] = true
			notify(player, extra)
		end
	end)
	player.CharacterAdded:Connect(function()
		local extra = getExtra(player)
		penalized[player] = nil -- personagem novo, velocidade original
		if extra then
			task.defer(applyEffect, player, extra)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do
	watch(p)
end
Players.PlayerRemoving:Connect(function(p)
	announced[p] = nil
	penalized[p] = nil
end)

-- Decaimento.
task.spawn(function()
	local hungerClock, energyClock = 0, 0
	while true do
		local dt = task.wait(1)
		hungerClock += dt
		energyClock += dt
		local dropHunger = hungerClock >= HUNGER_DECAY_INTERVAL
		local dropEnergy = energyClock >= ENERGY_DECAY_INTERVAL
		if dropHunger then
			hungerClock -= HUNGER_DECAY_INTERVAL
		end
		if dropEnergy then
			energyClock -= ENERGY_DECAY_INTERVAL
		end
		if dropHunger or dropEnergy then
			for _, p in Players:GetPlayers() do
				if announced[p] then
					if dropHunger then
						NeedsService.AddHunger(p, -1)
					end
					if dropEnergy then
						NeedsService.AddEnergy(p, -1)
					end
				end
			end
		end
	end
end)

return NeedsService
