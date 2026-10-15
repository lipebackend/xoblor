-- Regras puras de fome/energia (0-100), testadas com lune em tests/.
local NeedsLogic = {}
NeedsLogic.MAX_NEED = 100

-- Valor salvo -> inteiro em [0, 100]. Ausente/NaN vira 100 (perfil novo).
function NeedsLogic.Clamp(n)
	n = tonumber(n)
	if n == nil or n ~= n then
		return NeedsLogic.MAX_NEED
	end
	return math.clamp(math.floor(n), 0, NeedsLogic.MAX_NEED)
end

function NeedsLogic.ValidDelta(n)
	return type(n) == "number" and n == n and n % 1 == 0 and math.abs(n) <= 1e6
end

function NeedsLogic.Apply(current, n)
	return math.clamp(current + n, 0, NeedsLogic.MAX_NEED)
end

function NeedsLogic.IsExhausted(hunger, energy)
	return hunger <= 0 or energy <= 0
end

return NeedsLogic
