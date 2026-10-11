-- GamePasses do xoblor. Troque os IDs pelos reais do Creator Hub (0 = desativado).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local GamePasses = {
	IDS = {
		VIP = 0, -- salário x1,5 (JobService)
		CasaBarra = 0, -- libera a Mansão na Barra
		ViaturaTurbo = 0, -- viatura mais rápida
	},
}
local cache = {} -- [player][name] = bool

function GamePasses.Owns(player, name)
	local id = GamePasses.IDS[name]
	if not id or id == 0 then
		return false
	end
	cache[player] = cache[player] or {}
	if cache[player][name] ~= nil then
		return cache[player][name]
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
	if ok then
		cache[player][name] = owns
	end
	return ok and owns or false
end

-- compra feita dentro do jogo: atualiza o cache na hora
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	if not bought then
		return
	end
	for name, id in pairs(GamePasses.IDS) do
		if id == passId then
			cache[player] = cache[player] or {}
			cache[player][name] = true
		end
	end
end)
Players.PlayerRemoving:Connect(function(p)
	cache[p] = nil
end)

return GamePasses
