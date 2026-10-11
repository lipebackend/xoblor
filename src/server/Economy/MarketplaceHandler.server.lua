local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)

-- ProductId -> moedas (troque pelos IDs reais do Creator Hub)
local PRODUCTS = {
	[1] = 500,
	[2] = 1200,
}

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player or not Economy.IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local amount = PRODUCTS[info.ProductId]
	if not amount then
		warn("[Marketplace] ProductId desconhecido: " .. info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local extra = Data.GetExtra(player)
	extra.Receipts = extra.Receipts or {}
	if not extra.Receipts[info.PurchaseId] then
		local ok = Economy.AddCoins(player, amount, "robux:" .. info.ProductId)
		if not ok then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		extra.Receipts[info.PurchaseId] = os.time()
	end
	if not Data.SaveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
