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
-- UserId: inteiro != 0. Produção: 1..2^53. No Studio (Test com vários jogadores) os jogadores
-- locais têm UserId negativo (-1, -2, ...), então com `studio` = true aceita também -2^53..-1.
-- O flag é injetado (RemoteUtil passa RunService:IsStudio()); padrão = produção.
RemoteGuard.Studio = false
function RemoteGuard.SetStudio(on)
	RemoteGuard.Studio = on == true
end

function RemoteGuard.IsUserId(v, studio)
	if not RemoteGuard.IsInt(v, -RemoteGuard.MAX_USER_ID, RemoteGuard.MAX_USER_ID) or v == 0 then
		return false
	end
	return v > 0 or studio == true
end

V.UserId = function(v)
	return RemoteGuard.IsUserId(v, RemoteGuard.Studio)
end
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

-- Limitador por jogador (token bucket). buckets: tabela [player] = bucket (o chamador limpa na saída).
function RemoteGuard.Limiter(interval, burst, clock, buckets)
	buckets = buckets or {}
	return function(player)
		local ok
		ok, buckets[player] = RemoteGuard.Take(buckets[player], clock(), interval, burst)
		return ok
	end,
		buckets
end

-- Caminho de um RemoteFunction (OnServerInvoke): rate limit global e por remote, schema, pcall e log.
-- deps: global(player)/rate(player) -> bool, record(player, event, context, details) (SecurityLog),
-- flag(player, what, event, context) (strike), log(msg). handler(player, ...) -> ok, res...
function RemoteGuard.Invoker(name, args, handler, deps)
	return function(player, ...)
		-- igual ao de antes: o global conta toda chamada; o balde do remote só se o global passou
		local g = deps.global(player)
		if not g or not deps.rate(player) then
			deps.record(player, "rate_limit", name, "")
			return false, "RateLimited"
		end
		local valid, bad = RemoteGuard.Check(args, select("#", ...), { ... })
		if not valid then
			deps.flag(player, ("argumento %d inválido"):format(bad), "invalid_payload", name)
			return false, "Invalid"
		end
		-- repassa todos os retornos do handler (ex.: BankDeposit devolve ok, banco, movido)
		local r = table.pack(pcall(handler, player, ...))
		if not r[1] then
			deps.log(("[Remote] %s falhou: %s"):format(name, tostring(r[2])))
			return false, "ServerError"
		end
		if r[2] == false and r[3] == "Invalid" then
			deps.flag(player, "payload inválido", "invalid_payload", name)
		end
		return table.unpack(r, 2, r.n)
	end
end

return RemoteGuard
