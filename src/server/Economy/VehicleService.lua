-- Veículos: modelos em ServerStorage/Vehicles/<Id> (com PrimaryPart e VehicleSeat).
-- Posse em Extra.Vehicles (comprado no ShopService). 1 veículo ativo por jogador.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local JobService = require(script.Parent.JobService)
local RemoteUtil = require(script.Parent.RemoteUtil)
local Catalog = require(RS.Shared.ShopCatalog)

local VehicleService = {}
local rateOk = RemoteUtil.Limiter(2)
local active = {} -- [player] = Model
local MAX_SPAWN_DIST = 60

local function nearestSpawn(pos)
	local best, bestD
	for _, s in CollectionService:GetTagged("VehicleSpawn") do
		if s:IsA("BasePart") then
			local d = (s.Position - pos).Magnitude
			if not bestD or d < bestD then best, bestD = s, d end
		end
	end
	return best, bestD
end

function VehicleService.Despawn(p)
	if active[p] then active[p]:Destroy(); active[p] = nil end
end

function VehicleService.Spawn(p, id)
	if not Economy.IsLoaded(p) then return false, "NotLoaded" end
	local item = Catalog.Get(id)
	if not item or item.Category ~= "Veiculo" then return false, "UnknownVehicle" end
	local e = Data.GetExtra(p)
	if not (e and e.Vehicles and e.Vehicles[id]) then return false, "NotOwned" end
	if item.RequiredJob and JobService.GetJob(p) ~= item.RequiredJob then return false, "WrongJob" end
	local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, "NoCharacter" end
	local spot, dist = nearestSpawn(hrp.Position)
	if not spot or dist > MAX_SPAWN_DIST then return false, "NoSpawnNearby" end
	local src = ServerStorage:FindFirstChild("Vehicles") and ServerStorage.Vehicles:FindFirstChild(id)
	if not src then warn("[Vehicle] modelo ausente: " .. id); return false, "MissingModel" end

	VehicleService.Despawn(p) -- garante só um ativo
	local car = src:Clone()
	car.Name = p.Name .. "_" .. id
	car:SetAttribute("OwnerUserId", p.UserId)
	car:PivotTo(spot.CFrame + Vector3.new(0, 4, 0))
	car.Parent = workspace
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then pcall(function() part:SetNetworkOwner(p) end) end
	end
	-- só o dono dirige
	for _, seat in car:GetDescendants() do
		if seat:IsA("VehicleSeat") then
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				local h = seat.Occupant
				local who = h and Players:GetPlayerFromCharacter(h.Parent)
				if who and who ~= p then h.Sit = false; h.Jump = true end
			end)
		end
	end
	active[p] = car
	return true, id
end

function VehicleService.List(p)
	local e = Data.GetExtra(p)
	local out = {}
	for id in pairs(e and e.Vehicles or {}) do table.insert(out, id) end
	return out
end

RemoteUtil.Get("VehicleAction", "RemoteFunction").OnServerInvoke = function(p, action, id)
	if not rateOk(p) then return false, "RateLimited" end
	if action == "spawn" and type(id) == "string" then return VehicleService.Spawn(p, id)
	elseif action == "despawn" then VehicleService.Despawn(p); return true
	elseif action == "list" then return true, VehicleService.List(p) end
	return false, "Invalid"
end

Players.PlayerRemoving:Connect(VehicleService.Despawn)
return VehicleService
