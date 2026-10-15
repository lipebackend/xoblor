-- Loja: o menu chama RequestPurchase; a regra de compra fica em ShopPurchase.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Data = require(script.Parent.DataStoreHandler)
local JobService = require(script.Parent.JobService)
local RemoteUtil = require(script.Parent.RemoteUtil)
local ShopPurchase = require(script.Parent.ShopPurchase)
local Catalog = require(RS.Shared.ShopCatalog)

RemoteUtil.BindFunction("RequestPurchase", 0.5, 2, ShopPurchase.Purchase)

-- reveste roupas compradas ao renascer (só se ainda tiver o emprego exigido)
local function hookCharacter(p)
	p.CharacterAdded:Connect(function()
		task.wait(1)
		local extra = Data.GetExtra(p)
		for id in pairs(extra and extra.Owned or {}) do
			local item = Catalog.Get(id)
			if
				item
				and item.Category == "Roupa"
				and (not item.RequiredJob or JobService.GetJob(p) == item.RequiredJob)
			then
				ShopPurchase.Grant(p, item, extra)
			end
		end
	end)
end
Players.PlayerAdded:Connect(hookCharacter)
for _, p in Players:GetPlayers() do
	hookCharacter(p)
end
