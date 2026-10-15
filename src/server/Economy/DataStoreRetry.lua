-- Repetição de chamadas ao DataStore com backoff (regras puras, testadas com lune em tests/).
-- Tudo é injetado em `env`: clock (os.clock), wait (task.wait), budget (GetRequestBudgetForRequestType,
-- opcional), backoff (ProfileLogic.Backoff), rand (math.random), log (warn). Nos testes: relógio falso.

local DataStoreRetry = {}

DataStoreRetry.DEFAULTS = {
	attempts = 5, -- tentativas no total
	base = 1, -- backoff: base * 2^(i-1), com jitter "full", até cap (ProfileLogic.Backoff)
	cap = 8,
	budgetPoll = 0.5, -- intervalo entre consultas de orçamento
	maxBudgetWait = 30, -- espera máxima por orçamento sem prazo (autosave); depois tenta assim mesmo
	callMargin = 0, -- s reservados para a chamada terminar antes do prazo (latência do UpdateAsync)
}

local function opt(env, k)
	local v = env[k]
	if v == nil then
		return DataStoreRetry.DEFAULTS[k]
	end
	return v
end

-- Espera orçamento até o prazo (ou maxBudgetWait, se não houver prazo). Nunca fica preso.
local function waitBudget(env, deadline)
	if not env.budget then
		return
	end
	local limit = math.min(deadline, env.clock() + opt(env, "maxBudgetWait"))
	while env.budget() < 1 and env.clock() < limit do
		env.wait(math.min(opt(env, "budgetPoll"), limit - env.clock())) -- não passa do limite
	end
end

-- Roda fn() até dar certo, com no máximo `attempts` tentativas, backoff crescente com jitter e
-- sem passar do prazo (BindToClose). Retorna ok, resultado (ou último erro), tentativas feitas e,
-- na falha, o motivo da desistência: "exhausted" (acabaram as tentativas) ou "deadline".
function DataStoreRetry.Run(fn, env, deadline)
	deadline = deadline or math.huge
	local attempts = opt(env, "attempts")
	local ok, res
	local margin = opt(env, "callMargin")
	for i = 1, attempts do
		waitBudget(env, deadline - margin)
		-- sem tempo para a chamada terminar antes do prazo: desiste em vez de chamar atrasado
		if env.clock() + margin >= deadline then
			return false, res or "deadline", i - 1, "deadline"
		end
		ok, res = pcall(fn)
		if ok then
			return true, res, i
		end
		if env.log then
			env.log(("[DataStore] tentativa %d/%d falhou: %s"):format(i, attempts, tostring(res)))
		end
		if i == attempts then
			return false, res, i, "exhausted"
		end
		local delay = env.backoff(i, opt(env, "base"), opt(env, "cap"), env.rand)
		if env.clock() + delay + margin >= deadline then
			return false, res, i, "deadline"
		end
		env.wait(delay)
	end
	return false, res, attempts, "exhausted"
end

-- Classe curta do erro: o código HTTP ("... HTTP 429 ...") se houver, senão o primeiro código de
-- 3 dígitos (500, 502...), senão "error". Nunca devolve o texto do erro (pode citar chave/valor).
function DataStoreRetry.ErrorClass(err)
	local s = tostring(err)
	return s:match("HTTP (%d%d%d)%f[%D]") or s:match("%f[%d](%d%d%d)%f[%D]") or "error"
end

-- Details do evento save_failed do SecurityLog: só motivo, classe do erro e tentativas.
-- Nada do perfil (moedas, extra, prisão) entra aqui.
function DataStoreRetry.FailureDetails(err, attempts, why)
	return ("reason=%s error=%s attempts=%d"):format(
		why == "deadline" and "deadline" or "exhausted",
		DataStoreRetry.ErrorClass(err),
		tonumber(attempts) or 0
	)
end

return DataStoreRetry
