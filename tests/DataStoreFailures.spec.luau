-- Falhas de DataStore durante o autosave escalonado: DataStoreRetry + ProfileLogic + AutosaveSchedule
-- com um DataStore falso e relógio falso (nenhuma espera real).
local Retry = require("../src/server/Economy/DataStoreRetry")
local P = require("../src/server/Economy/ProfileLogic")
local S = require("../src/server/Economy/AutosaveSchedule")
local Sec = require("../src/server/Economy/SecurityLogic")

local THROTTLE = "502: API Services rejected request with error. HTTP 429 (Too Many Requests)"
local INTERNAL = "500: Internal Server Error"

-- DataStore falso: UpdateAsync aplica a transformação; `fail` decide se a chamada lança erro.
local function newStore()
	local st = { data = {}, calls = 0, writes = 0, fail = nil }
	function st:UpdateAsync(key, transform)
		self.calls += 1
		local err = self.fail and self.fail(self.calls, key)
		if err then
			error(err, 0)
		end
		local new = transform(self.data[key] and table.clone(self.data[key]) or nil)
		if new ~= nil then
			self.data[key] = new
			self.writes += 1
		end
		return new
	end
	-- SetAsync também falha do mesmo jeito (o jogo não usa, mas o mock cobre)
	function st:SetAsync(key, value)
		self.calls += 1
		local err = self.fail and self.fail(self.calls, key)
		if err then
			error(err, 0)
		end
		self.data[key] = value
		self.writes += 1
	end
	return st
end

-- Relógio falso: wait avança o tempo e registra as esperas.
local function newEnv(extra)
	local env = { t = 0, waits = {}, logs = {} }
	env.clock = function()
		return env.t
	end
	env.wait = function(d)
		assert(d > 0, "espera de 0s (hot loop)")
		table.insert(env.waits, d)
		env.t += d
	end
	env.backoff = P.Backoff
	env.rand = function()
		return 1 -- sem jitter: delays determinísticos
	end
	env.log = function(msg)
		table.insert(env.logs, msg)
	end
	for k, v in extra or {} do
		env[k] = v
	end
	return env
end

local JOB = "job-A"

-- Mesmo fluxo do DataStoreHandler.doSave: UpdateAsync + BuildSave dentro de retry e, na falha
-- final, um único SecurityLog.Record(player, "save_failed", "DataStore", FailureDetails(...)).
local function save(store, env, p, release, deadline)
	local owned = false
	local ok, err, n, why = Retry.Run(function()
		store:UpdateAsync("Player_" .. p.id, function(old)
			local new = P.BuildSave(old, JOB, env.t, p.coins, p.extra or {}, p.jail, release)
			owned = new ~= nil
			return new
		end)
	end, env, deadline)
	if not ok and env.records then
		table.insert(env.records, Sec.Entry("save_failed", p.id, "DataStore", Retry.FailureDetails(err, n, why), env.t))
	end
	return ok and owned, ok, n
end

return function(T)
	local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

	describe("DataStoreRetry", function()
		it("erro transitório: repete com espera crescente e salva", function()
			local store = newStore()
			store.fail = function(n)
				return n <= 2 and THROTTLE or nil
			end
			local env = newEnv()
			local okSave, ok, n = save(store, env, { id = 1, coins = 50 }, false)
			eq(ok, true)
			eq(okSave, true)
			eq(n, 3)
			eq(#env.waits, 2)
			eq(env.waits[1], 1)
			eq(env.waits[2], 2)
			eq(store.data.Player_1.Coins, 50)
			eq(#env.logs, 2)
			truthy(env.logs[1]:find("429", 1, true) ~= nil)
			truthy(env.logs[1]:find("tentativa 1/5", 1, true) ~= nil)
		end)

		it("falha permanente: tentativas limitadas, delays crescentes até o teto, sem hot loop", function()
			local store = newStore()
			store.fail = function()
				return INTERNAL
			end
			local env = newEnv()
			local okSave, ok, n = save(store, env, { id = 1, coins = 50 }, false)
			eq(ok, false)
			eq(okSave, false)
			eq(n, 5)
			eq(store.calls, 5)
			eq(#env.waits, 4) -- não espera depois da última
			for i = 2, #env.waits do
				truthy(env.waits[i] >= env.waits[i - 1])
				truthy(env.waits[i] <= Retry.DEFAULTS.cap)
			end
			eq(env.t, 1 + 2 + 4 + 8)
			eq(#env.logs, 5)
			eq(store.data.Player_1, nil)
		end)

		it("com jitter, cada espera fica entre 0 e o teto da tentativa", function()
			local store = newStore()
			store.fail = function()
				return THROTTLE
			end
			local seq, k = { 0.3, 0.9, 0.1, 0.7 }, 0
			local env = newEnv({
				rand = function()
					k += 1
					return seq[k]
				end,
			})
			-- jitter 0 viraria espera 0: o teste exige > 0, então a sequência evita 0
			save(store, env, { id = 1, coins = 1 }, false)
			for i, w in env.waits do
				truthy(w > 0 and w <= math.min(8, 2 ^ (i - 1)))
			end
		end)

		it("prazo do BindToClose: para antes de passar do prazo", function()
			local store = newStore()
			store.fail = function()
				return THROTTLE
			end
			local env = newEnv()
			local _, ok = save(store, env, { id = 1, coins = 1 }, true, 5)
			eq(ok, false)
			truthy(env.t < 5)
			eq(store.calls, 3) -- 0s, 1s, 3s; a próxima espera (4s) passaria de 5s
		end)

		it("sem orçamento: espera limitada (maxBudgetWait) e tenta assim mesmo", function()
			local store = newStore()
			local env = newEnv({
				budget = function()
					return 0
				end,
			})
			local okSave = save(store, env, { id = 1, coins = 7 }, false)
			eq(okSave, true)
			eq(env.t, Retry.DEFAULTS.maxBudgetWait)
			eq(#env.waits, Retry.DEFAULTS.maxBudgetWait / Retry.DEFAULTS.budgetPoll)
		end)

		it("orçamento volta: tenta assim que houver", function()
			local store = newStore()
			local env
			env = newEnv({
				budget = function()
					return env.t >= 2 and 1 or 0
				end,
			})
			save(store, env, { id = 1, coins = 7 }, false)
			eq(env.t, 2)
			eq(store.calls, 1)
		end)

		it("SetAsync falhando também é repetido", function()
			local store = newStore()
			store.fail = function(n)
				return n == 1 and THROTTLE or nil
			end
			local env = newEnv()
			local ok, _, n = Retry.Run(function()
				store:SetAsync("k", { v = 1 })
			end, env)
			eq(ok, true)
			eq(n, 2)
			eq(store.data.k.v, 1)
		end)
	end)

	describe("autosave escalonado com DataStore instável", function()
		-- 10 jogadores, 10 min de jogo; moedas mudam a cada tick; ~30% das chamadas falham
		-- e há uma janela de throttling total entre 120s e 200s.
		local function simulate(seed)
			math.randomseed(seed)
			local store = newStore()
			local env = newEnv()
			store.fail = function()
				if env.t >= 120 and env.t < 200 then
					return THROTTLE
				end
				return math.random() < 0.3 and INTERNAL or nil
			end
			local sched = S.New(60)
			local players = {}
			for i = 1, 10 do
				local p = { id = i, coins = 0, lastSaved = nil }
				players[i] = p
				-- load: trava a sessão
				store.data["Player_" .. i] = { Coins = 0, Version = 2, SessionJobId = JOB, SessionTime = 0 }
				S.Add(sched, p, env.t)
			end
			local dueCount = {}
			while env.t < 600 do
				env.t += 1 -- tick do agendador (AUTOSAVE_TICK)
				for _, p in players do
					p.coins += 1 -- dado sujo
				end
				for _, p in S.Due(sched, env.t) do
					dueCount[p] = (dueCount[p] or 0) + 1
					local snapshot = p.coins
					if save(store, env, p, false) then
						p.lastSaved = snapshot
					end
				end
			end
			return store, env, players, dueCount
		end

		it("agenda não acumula: cada jogador sai no Due no máximo 1x por intervalo", function()
			local _, env, players, dueCount = simulate(7)
			for _, p in players do
				truthy(dueCount[p] <= math.ceil(env.t / 60) + 1)
				truthy(dueCount[p] >= 1)
			end
		end)

		it("o que foi gravado é sempre o último snapshot salvo com sucesso (nada mais velho)", function()
			local store, _, players = simulate(11)
			for _, p in players do
				local rec = store.data["Player_" .. p.id]
				if p.lastSaved then
					eq(rec.Coins, p.lastSaved)
				end
				eq(rec.SessionJobId, JOB) -- trava mantida durante as falhas
			end
		end)

		it("saída depois das falhas: save final com release grava o valor atual e solta a trava", function()
			local store, env, players = simulate(13)
			store.fail = function(n)
				return n % 2 == 0 and THROTTLE or nil -- ainda instável
			end
			for _, p in players do
				local okSave = save(store, env, p, true, env.t + 25)
				eq(okSave, true)
				local rec = store.data["Player_" .. p.id]
				eq(rec.Coins, p.coins) -- nada perdido
				eq(rec.SessionJobId, nil)
			end
		end)

		it("trava de outro servidor: save não sobrescreve (nem depois de repetir)", function()
			local store = newStore()
			store.data.Player_1 = { Coins = 999, Version = 2, SessionJobId = "job-B", SessionTime = 0 }
			store.fail = function(n)
				return n == 1 and THROTTLE or nil
			end
			local env = newEnv()
			local okSave, ok = save(store, env, { id = 1, coins = 5 }, false)
			eq(ok, true)
			eq(okSave, false) -- DataStoreHandler trata como trava perdida (session_lock_lost + kick)
			eq(store.data.Player_1.Coins, 999)
			eq(store.writes, 0)
		end)

		it("throttling total no fechamento: desiste dentro do prazo e registra cada falha", function()
			local store = newStore()
			store.fail = function()
				return THROTTLE
			end
			local env = newEnv()
			env.t = 1000
			local deadline = env.t + 25 -- CLOSE_TIMEOUT
			local _, ok, n = save(store, env, { id = 1, coins = 5 }, true, deadline)
			eq(ok, false)
			truthy(env.t <= deadline)
			eq(#env.logs, n)
		end)
	end)

	describe("SecurityLog save_failed (só a falha final)", function()
		local function envWithRecords(extra)
			local env = newEnv(extra)
			env.records = {}
			return env
		end
		local function noProfileData(details, p)
			truthy(details:find(tostring(p.coins), 1, true) == nil, "moedas no details")
			truthy(details:find("Coins", 1, true) == nil)
			truthy(details:find("Player_", 1, true) == nil, "chave no details")
			truthy(details:find("Pizza", 1, true) == nil, "extra no details")
		end

		it("evento registrado", function()
			eq(Sec.EVENTS.save_failed, true)
		end)

		it("falha final: exatamente um save_failed com userId, motivo, classe e tentativas", function()
			local store = newStore()
			store.fail = function()
				return THROTTLE
			end
			local env = envWithRecords()
			local p = { id = 42, coins = 987654, extra = { Inventory = { "Pizza" } } }
			save(store, env, p, false)
			eq(#env.records, 1)
			local e = env.records[1]
			eq(e.event, "save_failed")
			eq(e.userId, 42)
			eq(e.context, "DataStore")
			eq(e.details, "reason=exhausted error=429 attempts=5")
			eq(#env.logs, 5) -- warns por tentativa continuam
			noProfileData(e.details, p)
		end)

		it("sucesso depois de repetir: nenhum save_failed", function()
			local store = newStore()
			store.fail = function(n)
				return n <= 3 and INTERNAL or nil
			end
			local env = envWithRecords()
			local okSave = save(store, env, { id = 1, coins = 5 }, false)
			eq(okSave, true)
			eq(#env.records, 0)
			eq(#env.logs, 3)
		end)

		it("desistência pelo prazo: um save_failed com reason=deadline", function()
			local store = newStore()
			store.fail = function()
				return INTERNAL
			end
			local env = envWithRecords()
			local p = { id = 7, coins = 31337 }
			save(store, env, p, true, 5)
			eq(#env.records, 1)
			eq(env.records[1].details, "reason=deadline error=500 attempts=3")
			noProfileData(env.records[1].details, p)
		end)

		it("erro com texto/valores do perfil: details só leva a classe", function()
			local store = newStore()
			store.fail = function()
				return "Player_9 Coins=555444 Pizza: value too large"
			end
			local env = envWithRecords()
			local p = { id = 9, coins = 555444, extra = { Inventory = { "Pizza" } } }
			save(store, env, p, false)
			eq(#env.records, 1)
			eq(env.records[1].details, "reason=exhausted error=error attempts=5")
			noProfileData(env.records[1].details, p)
			noProfileData(Sec.Format(env.records[1]), p)
		end)

		it("ErrorClass pega só códigos de 3 dígitos isolados", function()
			eq(Retry.ErrorClass(THROTTLE), "429") -- código HTTP tem prioridade sobre o 502 do prefixo
			eq(Retry.ErrorClass(INTERNAL), "500")
			eq(Retry.ErrorClass("HTTP 429 (Too Many Requests)"), "429")
			eq(Retry.ErrorClass("timeout 12345"), "error")
			eq(Retry.ErrorClass(nil), "error")
		end)
	end)
end
