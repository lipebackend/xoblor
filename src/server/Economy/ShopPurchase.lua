-- Compra de itens da loja, compartilhada pelo RequestPurchase (menu) e pelo InteractService (lojas do mapa).
-- Preço e requisito de emprego conferidos no servidor.
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local JobService = require(script.Parent.JobService)
local RemoteUtil = require(script.Parent.RemoteUtil)
local NeedsService = require(script.Parent.NeedsService)
local Catalog = require(RS.Shared.ShopCatalog)

local ShopPurchase = {}

function ShopPurchase.Grant(player, item, _extra)
	if item.Category == "Comida" then
		if item.Hunger then
			NeedsService.AddHunger(player, item.Hunger)
		end
		if item.Energy then
			NeedsService.AddEnergy(player, item.Energy)
		end
	elseif item.Category == "Roupa" then
		local outfit = ServerStorage:FindFirstChild("Outfits") and ServerStorage.Outfits:FindFirstChild(item.Id)
		local char = player.Character
		if outfit and char then
			for _, c in outfit:GetChildren() do
				local old = char:FindFirstChildOfClass(c.ClassName)
				if old and (c:IsA("Shirt") or c:IsA("Pants")) then
					old:Destroy()
				end
				c:Clone().Parent = char
			end
		end
	end
	-- Veiculo: só registra a posse; o spawn é do VehicleService.
end

function ShopPurchase.Purchase(player, itemId)
	if not RemoteUtil.IsId(itemId) then
		return false, "Invalid"
	end
	local item = Catalog.Get(itemId)
	if not item then
		return false, "UnknownItem"
	end
	if not Economy.IsLoaded(player) then
		return false, "NotLoaded"
	end
	if item.RequiredJob and JobService.GetJob(player) ~= item.RequiredJob then
		return false, "WrongJob"
	end

	local extra = Data.GetExtra(player)
	extra.Owned = extra.Owned or {}
	extra.Vehicles = extra.Vehicles or {}
	local owned = item.Category == "Veiculo" and extra.Vehicles[item.Id] or extra.Owned[item.Id]
	if item.Unique and owned then
		return false, "AlreadyOwned"
	end

	local res = 0
	if not RemoteUtil.IsInt(item.Price, 0) then
		return false, "UnknownItem"
	end
	if item.Price > 0 then
		local ok
		ok, res = Economy.SpendCoins(player, item.Price, "shop:" .. item.Id)
		if not ok then
			return false, res
		end
	end
	if item.Category == "Veiculo" then
		extra.Vehicles[item.Id] = true
	elseif item.Unique then
		extra.Owned[item.Id] = true
	end
	ShopPurchase.Grant(player, item, extra)
	return true, res
end

return ShopPurchase
