local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local Bank = require(script.Parent.BankService)
local Logic = require(script.Parent.EconomyLogic)

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
		-- Moedas pagas não podem sumir: o que não cabe na carteira vai para o banco.
		-- Se nem o banco tiver espaço (os dois no teto de 1e12), concede mesmo assim e registra:
		-- recusar faria o Roblox repetir a compra para sempre sem nunca caber.
		local okB, wallet = Economy.GetBalance(player)
		local _, bank = Bank.GetBank(player)
		if not okB or type(bank) ~= "number" then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local toWallet, toBank, lost = Logic.SplitCredit(wallet, bank, amount)
		if toWallet > 0 and not Economy.AddCoins(player, toWallet, "robux:" .. info.ProductId) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if toBank > 0 then
			lost += toBank - Bank.CreditBank(player, toBank)
		end
		if lost > 0 then
			warn(
				("[Marketplace] compra %s de %d: %d moedas não couberam (carteira e banco no teto)"):format(
					tostring(info.PurchaseId),
					player.UserId,
					lost
				)
			)
		end
		extra.Receipts[info.PurchaseId] = os.time()
	end
	if not Data.SaveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
