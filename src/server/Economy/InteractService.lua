-- Lojas e caixas eletrônicos do mapa: partes com tag "Shop" e atributo Category.
-- Category = "Banco" vira caixa eletrônico (carteira <-> banco via BankService); as outras abrem a loja
-- daquela categoria (compra via ShopPurchase). O ProximityPrompt abre uma sessão ligada à parte e
-- toda chamada confere a sessão e a distância até a parte. Regras puras em InteractLogic.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local RemoteUtil = require(script.Parent.RemoteUtil)
local BankService = require(script.Parent.BankService)
local Economy = require(script.Parent.EconomyService)
local ShopPurchase = require(script.Parent.ShopPurchase)
local InteractLogic = require(script.Parent.InteractLogic)
local Catalog = require(RS.Shared.ShopCatalog)

local InteractService = {}
local openEvent = RemoteUtil.Get("InteractOpen", "RemoteEvent")
local sessions = {} -- [player] = { Kind, Category, Part, OpenedAt }
local promptOk = RemoteUtil.Limiter(1, 2)

local function distanceTo(player, part)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not part:IsDescendantOf(workspace) then
		return nil
	end
	return (part.Position - root.Position).Magnitude
end

-- Confere sessão + distância. Retorna a sessão ou nil, erro.
local function session(player, kind)
	local s = sessions[player]
	local err = InteractLogic.CheckSession(s, kind, s and distanceTo(player, s.Part), os.clock())
	if err then
		if err ~= "NoSession" then
			sessions[player] = nil
		end
		return nil, err
	end
	return s
end

local function hook(part)
	if not part:IsA("BasePart") or part:FindFirstChild("InteractPrompt") then
		return
	end
	local category = part:GetAttribute("Category")
	local kind = InteractLogic.KindOf(category)
	if not kind then
		warn("[Interact] parte Shop com Category inválida: " .. part:GetFullName())
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "InteractPrompt"
	prompt.ActionText = kind == "ATM" and "Usar caixa eletrônico" or "Abrir loja"
	prompt.ObjectText = part.Name:gsub("_", " ")
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = InteractLogic.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if not promptOk(player) or not Economy.IsLoaded(player) then
			return
		end
		local dist = distanceTo(player, part)
		if not dist or dist > InteractLogic.MAX_DISTANCE then
			return
		end
		sessions[player] = { Kind = kind, Category = category, Part = part, OpenedAt = os.clock() }
		local payload = { Kind = kind, Category = category, Name = prompt.ObjectText }
		if kind == "Shop" then
			payload.Items = InteractLogic.ItemsFor(Catalog.Items, category)
		else
			local _, bank = BankService.GetBank(player)
			local _, wallet = Economy.GetBalance(player)
			payload.Bank, payload.Wallet = bank, wallet
		end
		openEvent:FireClient(player, payload)
	end)
end

-- Compra na loja do mapa: só itens da categoria da loja aberta, regra completa em ShopPurchase.
RemoteUtil.BindFunction("StoreBuy", 0.5, 2, function(player, itemId)
	if not RemoteUtil.IsId(itemId) then
		return false, "Invalid"
	end
	local s, err = session(player, "Shop")
	if not s then
		return false, err
	end
	local bad = InteractLogic.CanBuyHere(Catalog.Get(itemId), s.Category)
	if bad then
		return false, bad
	end
	return ShopPurchase.Purchase(player, itemId)
end)

-- Caixa eletrônico: action = "balance" | "deposit" | "withdraw". Devolve ok, { Wallet, Bank } ou erro.
RemoteUtil.BindFunction("AtmAction", 0.5, 2, function(player, action, amount)
	if action ~= "balance" and action ~= "deposit" and action ~= "withdraw" then
		return false, "Invalid"
	end
	if action ~= "balance" and not InteractLogic.ValidAmount(amount) then
		return false, "Invalid"
	end
	local s, err = session(player, "ATM")
	if not s then
		return false, err
	end
	if action == "deposit" then
		local ok, res = BankService.Deposit(player, amount)
		if not ok then
			return false, res
		end
	elseif action == "withdraw" then
		local ok, res = BankService.Withdraw(player, amount)
		if not ok then
			return false, res
		end
	end
	local okB, bank = BankService.GetBank(player)
	local okW, wallet = Economy.GetBalance(player)
	if not (okB and okW) then
		return false, "NotLoaded"
	end
	return true, { Wallet = wallet, Bank = bank }
end)

RemoteUtil.BindFunction("InteractClose", 0.5, 2, function(player)
	sessions[player] = nil
	return true
end)

CollectionService:GetInstanceAddedSignal("Shop"):Connect(hook)
for _, part in CollectionService:GetTagged("Shop") do
	hook(part)
end

Players.PlayerRemoving:Connect(function(p)
	sessions[p] = nil
end)

return InteractService
