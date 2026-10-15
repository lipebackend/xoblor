-- Regras puras de prisão (polícia x procurado), testadas com lune em tests/.
local ArrestLogic = {}

-- Todos os padrões ficam aqui; mude só esta tabela para ajustar.
ArrestLogic.Config = {
	SENTENCE_BASE = 60, -- segundos de cadeia
	SENTENCE_PER_100 = 1, -- + segundos a cada R$100 roubados enquanto procurado
	SENTENCE_MAX = 180,
	FINE_PCT = 20, -- % da carteira (nunca o banco), paga ao policial que prendeu
	VICTIM_REFUND = false, -- devolve o roubado às vítimas (desligado por padrão)
	ARREST_DISTANCE = 8, -- studs entre policial e procurado
	ARREST_COOLDOWN = 10, -- segundos entre prisões do mesmo policial
	JAIL_RADIUS = 15, -- se sair disto da cadeia, volta pra dentro
	-- o que o preso não pode fazer
	BLOCKED = { Rob = true, Buy = true, Pix = true, Job = true },
}

local function num(n)
	n = tonumber(n)
	if n == nil or n ~= n or n < 0 or n == math.huge then
		return 0
	end
	return n
end

-- Pena em segundos para `loot` reais roubados.
function ArrestLogic.Sentence(loot, cfg)
	cfg = cfg or ArrestLogic.Config
	local extra = math.floor(num(loot) / 100) * cfg.SENTENCE_PER_100
	return math.min(cfg.SENTENCE_BASE + extra, cfg.SENTENCE_MAX)
end

-- Multa sobre a carteira (inteiro, nunca maior que a carteira).
function ArrestLogic.Fine(wallet, cfg)
	cfg = cfg or ArrestLogic.Config
	wallet = math.floor(num(wallet))
	return math.min(math.floor(wallet * cfg.FINE_PCT / 100), wallet)
end

-- nil se pode prender, senão o código do erro.
-- a = { CopIsPolice, CopJailed, CopCooldownUntil, TargetIsPolice, TargetWanted, TargetJailed, Distance, Now }
function ArrestLogic.CanArrest(a, cfg)
	cfg = cfg or ArrestLogic.Config
	if not a.CopIsPolice then
		return "NotPolice"
	end
	if a.CopJailed then
		return "Jailed"
	end
	if num(a.CopCooldownUntil) > a.Now then
		return "Cooldown"
	end
	if a.TargetJailed then
		return "AlreadyJailed"
	end
	if a.TargetIsPolice or not a.TargetWanted then
		return "NotWanted"
	end
	if type(a.Distance) ~= "number" or a.Distance ~= a.Distance or a.Distance > cfg.ARREST_DISTANCE then
		return "TooFar"
	end
	return nil
end

-- Formato salvo (campo de nível superior do perfil): Jail = { EndsAt = os.time() do fim, Reason = "" }.
-- Ausente, corrompido ou EndsAt = 0 significa solto.
function ArrestLogic.Normalize(jail)
	if type(jail) ~= "table" then
		return { EndsAt = 0, Reason = "" }
	end
	local endsAt = math.floor(num(jail.EndsAt))
	return { EndsAt = endsAt, Reason = type(jail.Reason) == "string" and jail.Reason or "" }
end

-- Segundos restantes de pena (0 = solto).
function ArrestLogic.Remaining(jail, now)
	local j = ArrestLogic.Normalize(jail)
	if j.EndsAt <= 0 then
		return 0
	end
	return math.max(0, j.EndsAt - now)
end

function ArrestLogic.IsJailed(jail, now)
	return ArrestLogic.Remaining(jail, now) > 0
end

function ArrestLogic.NewJail(now, sentence, reason)
	return { EndsAt = math.floor(now + num(sentence)), Reason = type(reason) == "string" and reason or "" }
end

-- O preso pode fazer `action`? (Rob, Buy, Pix, Job)
function ArrestLogic.Allowed(action, jailed, cfg)
	cfg = cfg or ArrestLogic.Config
	return not (jailed and cfg.BLOCKED[action])
end

-- Devolução às vítimas. victims = { {u = userId, v = valor}, ... } em ordem;
-- available = quanto ainda dá para tirar da carteira do ladrão. Retorna lista {u, v} e total.
function ArrestLogic.RefundPlan(victims, available, cfg)
	cfg = cfg or ArrestLogic.Config
	local out, total = {}, 0
	if not cfg.VICTIM_REFUND or type(victims) ~= "table" then
		return out, 0
	end
	local left = math.floor(num(available))
	for _, e in ipairs(victims) do
		if left <= 0 then
			break
		end
		local v = math.min(math.floor(num(type(e) == "table" and e.v)), left)
		if v > 0 and type(e.u) == "number" then
			table.insert(out, { u = e.u, v = v })
			left -= v
			total += v
		end
	end
	return out, total
end

return ArrestLogic
