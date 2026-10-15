-- Regras puras da carteira (sem serviços do Roblox), testadas com lune em tests/.
local EconomyLogic = {}
EconomyLogic.MAX_BALANCE = 1e12

function EconomyLogic.ValidAmount(n)
	return type(n) == "number" and n == n and n > 0 and n % 1 == 0 and n <= EconomyLogic.MAX_BALANCE
end

-- Saldo salvo -> inteiro em [0, MAX]. Lixo/NaN vira 0.
function EconomyLogic.NormalizeBalance(v)
	v = tonumber(v)
	if v == nil or v ~= v then
		return 0
	end
	return math.clamp(math.floor(v), 0, EconomyLogic.MAX_BALANCE)
end

-- Retorna true, novo saldo (limitado ao máximo) ou false, erro.
function EconomyLogic.Add(balance, amount)
	if not EconomyLogic.ValidAmount(amount) then
		return false, "InvalidAmount"
	end
	if balance == nil then
		return false, "NotLoaded"
	end
	return true, math.min(balance + amount, EconomyLogic.MAX_BALANCE)
end

function EconomyLogic.Spend(balance, amount)
	if not EconomyLogic.ValidAmount(amount) then
		return false, "InvalidAmount"
	end
	if balance == nil then
		return false, "NotLoaded"
	end
	if balance < amount then
		return false, "InsufficientFunds"
	end
	return true, balance - amount
end

-- true, novo saldo de origem, novo saldo de destino; ou false, erro (nada muda).
-- Recusa se o destino passaria do máximo (antes o excedente sumia).
function EconomyLogic.Transfer(fromBalance, toBalance, amount, samePlayer)
	if samePlayer then
		return false, "SamePlayer"
	end
	if not EconomyLogic.ValidAmount(amount) then
		return false, "InvalidAmount"
	end
	if fromBalance == nil or toBalance == nil then
		return false, "NotLoaded"
	end
	if fromBalance < amount then
		return false, "InsufficientFunds"
	end
	if toBalance + amount > EconomyLogic.MAX_BALANCE then
		return false, "RecipientFull"
	end
	return true, fromBalance - amount, toBalance + amount
end

-- Pix: soma o que foi usado na janela e devolve (usado, log só com entradas vivas).
function EconomyLogic.PixUsed(log, now, window)
	local used, kept = 0, {}
	for _, e in ipairs(log) do
		if now - e.t < window then
			used += e.v
			table.insert(kept, e)
		end
	end
	return used, kept
end

return EconomyLogic
