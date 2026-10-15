-- Regras puras do perfil salvo (trava de sessão, backoff, schema/migração), testadas com lune.
local ProfileLogic = {}

ProfileLogic.SCHEMA_VERSION = 2
ProfileLogic.LOCK_TIMEOUT = 300 -- trava sem heartbeat (autosave) há 5 min é considerada morta

-- Decide a trava ao carregar. Retorna "acquire" (livre ou nossa), "stale" (trava morta, tomamos)
-- ou "locked" (outro servidor vivo). Trava viva nunca é roubada: evita duplicação.
function ProfileLogic.LockDecision(old, jobId, now, timeout)
	timeout = timeout or ProfileLogic.LOCK_TIMEOUT
	local owner = type(old) == "table" and old.SessionJobId or nil
	if owner == nil or owner == jobId then
		return "acquire"
	end
	local t = tonumber(old.SessionTime) or 0
	if now - t >= timeout then
		return "stale"
	end
	return "locked"
end

-- Espera antes da tentativa `attempt` (1 = primeira repetição): base * 2^(attempt-1), até cap,
-- com jitter "full" (0..valor). rand é uma função 0..1 (math.random nos servidores).
function ProfileLogic.Backoff(attempt, base, cap, rand)
	local ceiling = math.min(cap, base * 2 ^ (attempt - 1))
	return ceiling * (rand and rand() or 1)
end

local function int(n, min)
	n = tonumber(n)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return min
	end
	return math.max(math.floor(n), min)
end

-- Campo de prisão (Programador 5, #23): Jail = { Remaining = 0, Reason = "" }.
-- Remaining = segundos de pena restantes (só conta online; pode ser fracionário, arredondado para cima
-- como em ArrestLogic.Normalize); 0 = solto. Legado EndsAt é descartado (= solto), igual ao ArrestLogic.
function ProfileLogic.NormalizeJail(j)
	if type(j) ~= "table" then
		return { Remaining = 0, Reason = "" }
	end
	local r = tonumber(j.Remaining)
	if r == nil or r ~= r or r == math.huge or r <= 0 then
		return { Remaining = 0, Reason = "" }
	end
	local reason = type(j.Reason) == "string" and j.Reason:sub(1, 64) or ""
	return { Remaining = math.ceil(r), Reason = reason }
end

-- Aplica defaults e migrações. Retorna dados (cópia rasa nova) ou nil, "TooNew" se o perfil
-- foi gravado por uma versão mais nova do jogo (não carregar para não sobrescrever com menos campos).
function ProfileLogic.Migrate(old, now)
	old = type(old) == "table" and old or {}
	local v = int(old.Version, 0)
	if v > ProfileLogic.SCHEMA_VERSION then
		return nil, "TooNew"
	end
	local data = table.clone(old)
	-- v0/v1 -> v2: prisão adicionada
	data.Coins = int(data.Coins, 0)
	data.Extra = ProfileLogic.PersistableExtra(data.Extra)
	data.Jail = ProfileLogic.NormalizeJail(data.Jail, now)
	data.Version = ProfileLogic.SCHEMA_VERSION
	return data
end

-- Estado de desmaio (#26, Player.Downed/DownedLeft) é só de sessão e nunca é salvo:
-- sair ou resetar desmaiado conta como ir ao hospital. Estas chaves são removidas do Extra no save.
ProfileLogic.TRANSIENT_EXTRA = { "Downed", "DownedLeft", "Fainted" }

function ProfileLogic.PersistableExtra(extra)
	local out = type(extra) == "table" and table.clone(extra) or {}
	for _, k in ProfileLogic.TRANSIENT_EXTRA do
		out[k] = nil
	end
	return out
end

-- Monta o registro a gravar (só campos conhecidos: nada além de Coins, Extra, Jail, Version e trava), ou nil se outro servidor é o dono (não sobrescreve).
function ProfileLogic.BuildSave(old, jobId, now, coins, extra, jail, release)
	if type(old) == "table" and old.SessionJobId ~= nil and old.SessionJobId ~= jobId then
		return nil
	end
	if type(old) == "table" and int(old.Version, 0) > ProfileLogic.SCHEMA_VERSION then
		return nil
	end
	return {
		Coins = coins,
		Extra = ProfileLogic.PersistableExtra(extra),
		Jail = ProfileLogic.NormalizeJail(jail, now),
		Version = ProfileLogic.SCHEMA_VERSION,
		SessionJobId = (not release) and jobId or nil,
		SessionTime = now,
	}
end

return ProfileLogic
