-- Detecção de AFK no servidor: deslocamento do HumanoidRootPart e ações recebidas pelo servidor.
-- Nunca confia num "estou ativo" do cliente. Player.Idled é só sinal auxiliar (ver AfkLogic.MarkIdled).
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Logic = require(script.Parent.AfkLogic)
local Config = require(script.Parent.AfkConfig)

local AfkService = {}
local states = {} -- [player] = estado do AfkLogic

local function now()
	return os.clock()
end

local function rootPos(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function stateOf(player)
	local s = states[player]
	if not s then
		s = Logic.New(now())
		states[player] = s
	end
	return s
end

-- Atividade = movimento (amostras abaixo) ou interação real da lista em AfkConfig.INTERACTIONS.
-- Chamadas de remote NÃO contam: um script de exploit chama remotes sem sair do lugar.
function AfkService.MarkInteraction(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		Logic.MarkInteraction(stateOf(player), now(), Config)
	end
end

-- Tipo de interação de um ProximityPrompt (nil se não está na lista).
function AfkService.Classify(prompt)
	local kind = prompt.Name
	local door = prompt.Parent
	if door and door.Name == "Door" then
		local m = door:FindFirstAncestorOfClass("Model")
		while m and not CollectionService:HasTag(m, "House") do
			m = m:FindFirstAncestorOfClass("Model")
		end
		if m then
			kind = "HouseDoor"
		end
	end
	return Config.INTERACTIONS[kind] and kind or nil
end

-- PromptTriggered só dispara no servidor depois da checagem de distância/hold do próprio engine.
ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if AfkService.Classify(prompt) then
		AfkService.MarkInteraction(player)
	end
end)

-- Chamar depois de teleportar o jogador pelo servidor.
function AfkService.NotifyTeleport(player)
	Logic.Reanchor(stateOf(player), rootPos(player))
end

function AfkService.IsAfk(player)
	return Logic.IsAfk(stateOf(player), now(), Config)
end

local function watch(player)
	stateOf(player)
	player.CharacterAdded:Connect(function(char)
		-- respawn: nova posição vira âncora, sem contar como atividade
		local root = char:WaitForChild("HumanoidRootPart", 10)
		if root and states[player] then
			Logic.Reanchor(states[player], root.Position)
		end
	end)
	player.Idled:Connect(function(idleSeconds)
		if states[player] then
			Logic.MarkIdled(states[player], now(), idleSeconds)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do
	watch(p)
end
Players.PlayerRemoving:Connect(function(p)
	states[p] = nil
end)

task.spawn(function()
	while true do
		task.wait(Config.SAMPLE_INTERVAL)
		local t = now()
		for _, p in Players:GetPlayers() do
			local s = states[p]
			if s then
				Logic.Observe(s, rootPos(p), t, Config)
			end
		end
	end
end)

return AfkService
