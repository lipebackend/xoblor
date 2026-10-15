-- Regras puras das lojas e caixas eletrônicos do mapa (partes com tag "Shop"), testadas com lune em tests/.
local InteractLogic = {}
InteractLogic.PROMPT_DISTANCE = 10 -- MaxActivationDistance do ProximityPrompt
InteractLogic.MAX_DISTANCE = 14 -- tolerância no servidor (lag/posição do personagem)
InteractLogic.SESSION_TTL = 300 -- painel aberto expira em 5 min
InteractLogic.MAX_AMOUNT = 1e12

local SHOP_CATEGORIES = { Comida = true, Roupa = true, Veiculo = true }

-- "ATM" para Category = "Banco", "Shop" para categorias da loja, nil para o resto.
function InteractLogic.KindOf(category)
	if category == "Banco" then
		return "ATM"
	end
	if SHOP_CATEGORIES[category] then
		return "Shop"
	end
	return nil
end

-- Sessão = painel que o jogador abriu numa parte. Retorna nil se ainda vale, senão o erro.
-- `kind` é o tipo exigido pela chamada ("Shop" ou "ATM").
function InteractLogic.CheckSession(session, kind, distance, now)
	if type(session) ~= "table" then
		return "NoSession"
	end
	if session.Kind ~= kind then
		return "WrongPlace"
	end
	if now >= (session.OpenedAt or -math.huge) + InteractLogic.SESSION_TTL then
		return "Expired"
	end
	if type(distance) ~= "number" or distance ~= distance or distance > InteractLogic.MAX_DISTANCE then
		return "TooFar"
	end
	return nil
end

-- Ids dos itens de `items` (Catalog.Items) da categoria, em ordem estável (preço, depois id).
function InteractLogic.ItemsFor(items, category)
	local out = {}
	for id, item in pairs(items) do
		if type(item) == "table" and item.Category == category then
			table.insert(out, id)
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = items[a].Price or 0, items[b].Price or 0
		if pa ~= pb then
			return pa < pb
		end
		return a < b
	end)
	return out
end

-- Item pode ser comprado nesta loja? nil se sim.
function InteractLogic.CanBuyHere(item, storeCategory)
	if type(item) ~= "table" then
		return "UnknownItem"
	end
	if item.Category ~= storeCategory then
		return "WrongStore"
	end
	return nil
end

-- Valor de depósito/saque vindo do cliente.
function InteractLogic.ValidAmount(n)
	return type(n) == "number" and n == n and n % 1 == 0 and n >= 1 and n <= InteractLogic.MAX_AMOUNT
end

return InteractLogic
