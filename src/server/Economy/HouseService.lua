-- Casas: Model com tag "House" e atributo HouseId; dentro, uma Part "Door".
-- Extra.Houses[id] = "owned" | "rent"; Extra.RentUntil[id] = segundos de jogo acumulados até expirar.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local RemoteUtil = require(script.Parent.RemoteUtil)
local Catalog = require(RS.Shared.ShopCatalog)

local HouseService = {}
local rateOk = RemoteUtil.Limiter(0.5)
local housesChanged = RemoteUtil.Get("HousesChanged", "RemoteEvent")
local occupant = {} -- [houseId] = player (dono/inquilino atual no servidor)
local guests = {} -- [houseId] = { [userId] = true }
local models = {} -- [houseId] = Model

local function extraOf(p)
	if not Economy.IsLoaded(p) then return nil end
	local e = Data.GetExtra(p)
	if not e then return nil end
	e.Houses = e.Houses or {}
	e.RentUntil = e.RentUntil or {}
	e.PlayTime = tonumber(e.PlayTime) or 0 -- relógio de tempo de jogo
	return e
end

local function snapshot(e)
	local out = {}
	for id, kind in pairs(e.Houses) do
		out[id] = { Kind = kind, Left = kind == "rent" and math.max(0, (e.RentUntil[id] or 0) - e.PlayTime) or nil }
	end
	return out
end

local function notify(p, e) housesChanged:FireClient(p, snapshot(e)) end

local function release(id)
	occupant[id], guests[id] = nil, nil
	local m = models[id]
	if m then m:SetAttribute("OwnerUserId", 0) end
end

local function claim(p, id)
	if occupant[id] and occupant[id] ~= p then return false end
	occupant[id] = p
	guests[id] = guests[id] or {}
	if models[id] then models[id]:SetAttribute("OwnerUserId", p.UserId) end
	return true
end

function HouseService.CanEnter(p, id)
	local o = occupant[id]
	return o == p or (o ~= nil and guests[id] and guests[id][p.UserId] == true)
end

function HouseService.Rent(p, id)
	local h = Catalog.GetHouse(id); if not h then return false, "UnknownHouse" end
	local e = extraOf(p); if not e then return false, "NotLoaded" end
	if e.Houses[id] == "owned" then return false, "AlreadyOwned" end
	if occupant[id] and occupant[id] ~= p then return false, "Occupied" end
	local ok, res = Economy.SpendCoins(p, h.Rent, "house:rent:" .. id)
	if not ok then return false, res end
	e.Houses[id] = "rent"
	e.RentUntil[id] = math.max(e.RentUntil[id] or 0, e.PlayTime) + h.RentMinutes * 60
	claim(p, id); notify(p, e)
	return true, res
end

function HouseService.Buy(p, id)
	local h = Catalog.GetHouse(id); if not h then return false, "UnknownHouse" end
	local e = extraOf(p); if not e then return false, "NotLoaded" end
	if e.Houses[id] == "owned" then return false, "AlreadyOwned" end
	if occupant[id] and occupant[id] ~= p then return false, "Occupied" end
	local ok, res = Economy.SpendCoins(p, h.Price, "house:buy:" .. id)
	if not ok then return false, res end
	e.Houses[id] = "owned"; e.RentUntil[id] = nil
	claim(p, id); notify(p, e)
	return true, res
end

function HouseService.Invite(p, id, userId, allow)
	local e = extraOf(p); if not e or not e.Houses[id] then return false, "NotOwner" end
	if occupant[id] ~= p then return false, "NotOwner" end
	guests[id][userId] = allow and true or nil
	return true
end

-- Porta: só atravessa quem pode entrar (CanCollide por cliente via atributo não é seguro, então teleporta).
local function hookHouse(m)
	local id = m:GetAttribute("HouseId"); if not id then return end
	models[id] = m
	m:SetAttribute("OwnerUserId", 0)
	local door = m:FindFirstChild("Door", true); if not door then return end
	local inside = m:FindFirstChild("Inside", true) -- Part marcando o interior
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "Entrar", (Catalog.GetHouse(id) or {}).Name or id
	prompt.Parent = door
	prompt.Triggered:Connect(function(p)
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp and inside and HouseService.CanEnter(p, id) then
			hrp.CFrame = inside.CFrame + Vector3.new(0, 3, 0)
		end
	end)
end
CollectionService:GetInstanceAddedSignal("House"):Connect(hookHouse)
for _, m in CollectionService:GetTagged("House") do hookHouse(m) end

-- Ao entrar: reocupa casas (se livres). Aluguel corre por tempo de jogo.
local function onJoin(p)
	for _ = 1, 30 do if Economy.IsLoaded(p) then break end task.wait(1) end
	local e = extraOf(p); if not e then return end
	for id in pairs(e.Houses) do claim(p, id) end
	notify(p, e)
end
Players.PlayerAdded:Connect(onJoin)
for _, p in Players:GetPlayers() do task.spawn(onJoin, p) end

task.spawn(function()
	while true do
		task.wait(10)
		for _, p in Players:GetPlayers() do
			local e = extraOf(p)
			if e then
				e.PlayTime += 10
				for id, kind in pairs(e.Houses) do
					if kind == "rent" and e.PlayTime >= (e.RentUntil[id] or 0) then
						e.Houses[id], e.RentUntil[id] = nil, nil
						if occupant[id] == p then release(id) end
						notify(p, e)
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	for id, o in pairs(occupant) do if o == p then release(id) end end
end)

-- Remotes
RemoteUtil.Get("HouseAction", "RemoteFunction").OnServerInvoke = function(p, action, id, arg)
	if not rateOk(p) then return false, "RateLimited" end
	if type(action) ~= "string" or type(id) ~= "string" then return false, "Invalid" end
	if action == "rent" then return HouseService.Rent(p, id)
	elseif action == "buy" then return HouseService.Buy(p, id)
	elseif action == "invite" or action == "uninvite" then
		if type(arg) ~= "number" then return false, "Invalid" end
		return HouseService.Invite(p, id, arg, action == "invite")
	elseif action == "list" then
		local e = extraOf(p); if not e then return false, "NotLoaded" end
		return true, snapshot(e)
	end
	return false, "Invalid"
end

return HouseService
