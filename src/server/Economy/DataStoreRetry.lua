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
		env.wait(opt(env, "budgetPoll"))
	end
end

-- Roda fn() até dar certo, com no máximo `attempts` tentativas, backoff crescente com jitter e
-- sem passar do prazo (BindToClose). Retorna ok, resultado (ou último erro), tentativas feitas.
function DataStoreRetry.Run(fn, env, deadline)
	deadline = deadline or math.huge
	local attempts = opt(env, "attempts")
	local ok, res
	for i = 1, attempts do
		waitBudget(env, deadline)
		ok, res = pcall(fn)
		if ok then
			return true, res, i
		end
		if env.log then
			env.log(("[DataStore] tentativa %d/%d falhou: %s"):format(i, attempts, tostring(res)))
		end
		if i == attempts then
			break
		end
		local delay = env.backoff(i, opt(env, "base"), opt(env, "cap"), env.rand)
		if env.clock() + delay >= deadline then
			break
		end
		env.wait(delay)
	end
	return false, res, attempts
end

return DataStoreRetry
