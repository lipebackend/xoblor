-- Amostra a posição de cada jogador no servidor e detecta saltos impossíveis (teleporte do cliente).
-- Depois de um salto, assalto, reanimação e prisão ficam bloqueados por alguns segundos.
-- Só registra (SecurityLog, evento movement_jump): não expulsa nem gera Flag. Regras em MoveLogic.
-- Teleportes do próprio servidor devem chamar MovementService.AllowTeleport(player) antes de mover.
local Players = game:GetService("Players")
local Logic = require(script.Parent.MoveLogic)
local SecurityLog = require(script.Parent.SecurityLog)

local MovementService = {}
local Config = Logic.Config
local states = {}

local function stateOf(player)
	local s = states[player]
	if not s then
		s = Logic.New()
		states[player] = s
	end
	return s
end

function MovementService.AllowTeleport(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		Logic.AllowTeleport(stateOf(player), os.clock())
	end
end

-- Ações físicas (Rob, Revive, Arrest) chamam isto para o ator.
function MovementService.IsBlocked(player)
	return Logic.IsBlocked(states[player], os.clock())
end

local function sample(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local s = stateOf(player)
	if not (root and hum) then
		Logic.Sample(s, nil, os.clock(), 0)
		return
	end
	local seat = hum.SeatPart
	local seatSpeed = (seat and seat:IsA("VehicleSeat")) and seat.MaxSpeed or nil
	local maxSpeed = Logic.MaxSpeed(hum.WalkSpeed, seatSpeed)
	if Logic.Sample(s, root.Position, os.clock(), maxSpeed) == "jump" then
		SecurityLog.Record(
			player,
			"movement_jump",
			"Movement",
			("jumps=%d block=%ds"):format(s.Jumps, Config.BLOCK_SECONDS)
		)
	end
end

local function watch(player)
	stateOf(player)
	player.CharacterAdded:Connect(function()
		MovementService.AllowTeleport(player) -- respawn
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
		for _, p in Players:GetPlayers() do
			sample(p)
		end
	end
end)

return MovementService
