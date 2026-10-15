-- Regras puras de segurança dos remotes (rate limit, validação de argumentos, distância),
-- testadas com lune em tests/. Sem APIs do Roblox.
local RemoteGuard = {}

RemoteGuard.MAX_MONEY = 1e12 -- mesmo teto da carteira/banco
RemoteGuard.MAX_USER_ID = 2 ^ 53

-- Token bucket: `burst` chamadas seguidas, recarga de 1 a cada `interval` segundos.
-- bucket = { tokens, at } (criado se nil). Retorna ok, bucket.
function RemoteGuard.Take(bucket, now, interval, burst)
	burst = burst or 1
	if bucket == nil then
		bucket = { tokens = burst, at = now }
	end
	local dt = now - bucket.at
	if dt ~= dt or dt < 0 then
		dt = 0 -- relógio não deveria voltar; não recarrega
	end
	bucket.tokens = math.min(burst, bucket.tokens + dt / interval)
	bucket.at = now
	if bucket.tokens < 1 then
		return false, bucket
	end
	bucket.tokens -= 1
	return true, bucket
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
RemoteGuard.IsFinite = finite

function RemoteGuard.IsInt(n, min, max)
	return finite(n) and n % 1 == 0 and n >= (min or -math.huge) and n <= (max or math.huge)
end

function RemoteGuard.IsId(s)
	return type(s) == "string" and #s > 0 and #s <= 64 and s:match("^[%w_]+$") ~= nil
end

-- Validadores para schemas: cada um é function(v) -> boolean.
local V = {}
RemoteGuard.V = V

function V.Int(min, max)
	return function(v)
		return RemoteGuard.IsInt(v, min, max)
	end
end
V.Money = V.Int(1, RemoteGuard.MAX_MONEY)
V.UserId = V.Int(1, RemoteGuard.MAX_USER_ID)
V.Id = RemoteGuard.IsId

function V.OneOf(...)
	local set = {}
	for _, s in { ... } do
		set[s] = true
	end
	return function(v)
		return type(v) == "string" and set[v] == true
	end
end

-- nil (ou "", vindo de alguns clientes) passa; senão aplica `inner`.
function V.Optional(inner)
	return function(v)
		return v == nil or v == "" or inner(v)
	end
end

-- Confere os argumentos contra o schema. Argumentos a mais são recusados.
-- Retorna true, ou false e o índice (1-based) do primeiro argumento inválido.
function RemoteGuard.Check(schema, n, args)
	if n > #schema then
		return false, #schema + 1
	end
	for i, validate in schema do
		if not validate(args[i]) then
			return false, i
		end
	end
	return true
end

-- Distância entre duas posições (X/Y/Z) dentro de `max`, segura contra nil/NaN/inf.
function RemoteGuard.Within(a, b, max)
	if a == nil or b == nil then
		return false
	end
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	return finite(d) and d <= max, d
end

return RemoteGuard
