-- Regras puras do caixa eletrônico (resposta do AtmAction e mensagens pt-BR), sem APIs do Roblox.
-- Compartilhado: o servidor monta a resposta e o cliente formata as mensagens. Testado com lune em tests/.
local AtmLogic = {}

-- Mensagens dos códigos de erro devolvidos pelo servidor (BankService/EconomyService/InteractService).
AtmLogic.ERRORS = {
	BankFull = "Banco cheio: não cabe mais nada",
	WalletFull = "Carteira cheia: deposite antes de sacar",
	InsufficientFunds = "Sem grana",
	InvalidAmount = "Valor inválido",
	Invalid = "Valor inválido",
	NotLoaded = "Aguarde carregar",
	TooFar = "Chegue mais perto",
	Expired = "Abra de novo",
	NoSession = "Abra de novo",
	WrongPlace = "Abra de novo",
	RateLimited = "Calma aí",
	Jailed = "Você está preso",
	Downed = "Você está desmaiado",
	ServerError = "Erro, tente de novo",
}

local function int(n)
	n = tonumber(n)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return math.floor(n)
end

-- Resposta do AtmAction: Wallet e Bank como antes; Moved = valor movido de fato (0 em "balance").
function AtmLogic.Response(wallet, bank, moved)
	return { Wallet = wallet, Bank = bank, Moved = math.max(0, int(moved) or 0) }
end

function AtmLogic.ErrorMessage(code)
	return AtmLogic.ERRORS[code] or tostring(code)
end

-- Mensagem de sucesso. `format` = Catalog.FormatReais. Mostra o valor real e avisa se foi parcial.
function AtmLogic.SuccessMessage(action, requested, moved, format)
	moved, requested = int(moved), int(requested)
	if action == "balance" or moved == nil then
		return "Feito!"
	end
	local verb = action == "deposit" and "Depositado" or "Sacado"
	local text = ("%s %s"):format(verb, format(moved))
	if requested and moved < requested then
		local why = action == "deposit" and "banco no limite" or "carteira no limite"
		text ..= (" (de %s; %s)"):format(format(requested), why)
	end
	return text
end

return AtmLogic
