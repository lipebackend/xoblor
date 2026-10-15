-- BindToClose com 60 jogadores e orçamento baixo de DataStore: DataStoreClose + DataStoreRetry +
-- ProfileLogic com DataStore falso, orçamento que recarrega devagar e agendador cooperativo com
-- relógio falso (as "threads" são corrotinas; nenhuma espera real).
local Close = require("../src/server/Economy/DataStoreClose")
local Retry = require("../src/server/Economy/DataStoreRetry")
local P = require("../src/server/Economy/ProfileLogic")
local Sec = require("../src/server/Economy/SecurityLogic")

local THROTTLE = "502: API Services rejected request with error. HTTP 429 (Too Many Requests)"
local JOB = "job-A"
local TIMEOUT = 25 -- CLOSE_TIMEOUT do DataStoreHandler

-- Agendador: spawn roda na hora até a primeira espera (como task.spawn); wait cede e acorda depois.
local function newSim()
	local sim = { t = 0, sleeping = {} }
	function sim.clock()
		return sim.t
	end
	function sim.wait(d)
		assert(d > 0, "espera de 0s (hot loop)")
		local co = coroutine.running()
		table.insert(sim.sleeping, { co = co, at = sim.t + d })
		coroutine.yield()
	end
	local function resume(co)
		local ok, err = coroutine.resume(co)
		if not ok then
			error(err, 0)
		end
	end
	function sim.spawn(fn)
		resume(coroutine.create(fn))
	end
	-- roda fn como thread principal até ela terminar (ou o tempo estourar)
	function sim.run(fn, limit)
		local done = false
		sim.spawn(function()
			fn()
			done = true
		end)
		while not done do
			assert(#sim.sleeping > 0, "deadlock")
			local bi = 1
			for i, s in sim.sleeping do
				if s.at < sim.sleeping[bi].at then
					bi = i
				end
			end
			local s = table.remove(sim.sleeping, bi)
			sim.t = math.max(sim.t, s.at)
			assert(sim.t < limit, "simulação passou do limite")
			resume(s.co)
		end
	end
	return sim
end

-- Orçamento: começa com `start`, recarrega `rate`/s até `cap`. UpdateAsync gasta 1; sem orçamento,
-- falha com 429. Cada chamada leva `latency` s.
local function newStore(sim, start, rate, cap, latency)
	local st = { data = {}, tokens = start, last = 0, calls = 0, throttled = 0 }
	local function refill()
		st.tokens = math.min(cap, st.tokens + (sim.t - st.last) * rate)
		st.last = sim.t
	end
	function st.budget()
		refill()
		return math.floor(st.tokens)
	end
	function st:UpdateAsync(key, transform)
		self.calls += 1
		refill()
		if self.tokens < 1 then
			self.throttled += 1
			sim.wait(latency)
			error(THROTTLE, 0)
		end
		self.tokens -= 1
		sim.wait(latency)
		local new = transform(self.data[key] and table.clone(self.data[key]) or nil)
		if new ~= nil then
			self.data[key] = new
		end
		return new
	end
	return st
end

local function setup(n, start, rate, cap, latency, blind)
	local sim = newSim()
	local store = newStore(sim, start, rate, cap, latency)
	local players = {}
	for i = 1, n do
		players[i] = { UserId = i, coins = 1000 + i }
		store.data["Player_" .. i] = { Coins = 0, Version = 2, SessionJobId = JOB, SessionTime = 0 }
	end
	local env = {
		clock = sim.clock,
		wait = sim.wait,
		budget = not blind and store.budget or nil, -- blind: chama sem olhar o orçamento (gera 429)
		backoff = P.Backoff,
		rand = function()
			return 0.5
		end,
		callMargin = 1, -- igual ao DataStoreHandler
	}
	local out = { results = {}, records = {}, starts = {} }
	-- mesmo fluxo do saveAndRelease/doSave do DataStoreHandler (release = true)
	local function saveOne(p, deadline)
		out.starts[p] = (out.starts[p] or 0) + 1
		local ok, err, n, why = Retry.Run(function()
			store:UpdateAsync("Player_" .. p.UserId, function(old)
				return P.BuildSave(old, JOB, sim.t, p.coins, {}, nil, true)
			end)
		end, env, deadline)
		if not ok then
			table.insert(out.records, {
				at = sim.t,
				entry = Sec.Entry("save_failed", p.UserId, "DataStore", Retry.FailureDetails(err, n, why)),
			})
		end
		out.results[p] = { ok = ok, at = sim.t }
	end
	return sim, store, players, saveOne, out
end

return function(T)
	local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

	local function closeAll(n, start, rate, cap, latency, blind)
		local sim, store, players, saveOne, out = setup(n, start, rate, cap, latency, blind)
		local pending, deadline, returnedAt
		sim.run(function()
			pending, deadline =
				Close.Run(players, saveOne, { clock = sim.clock, wait = sim.wait, spawn = sim.spawn }, TIMEOUT)
			returnedAt = sim.t
		end, 120)
		return {
			sim = sim,
			store = store,
			players = players,
			out = out,
			pending = pending,
			deadline = deadline,
			returnedAt = returnedAt,
		}
	end

	local function checkInvariants(r)
		eq(r.deadline, TIMEOUT)
		truthy(r.returnedAt <= r.deadline, ("handler voltou em %.2fs"):format(r.returnedAt))
		eq(r.pending, 0)
		local failsByUser = {}
		for _, rec in r.out.records do
			truthy(rec.at <= r.deadline, "save_failed depois do prazo")
			eq(rec.entry.event, "save_failed")
			failsByUser[rec.entry.userId] = (failsByUser[rec.entry.userId] or 0) + 1
		end
		local okCount, failCount = 0, 0
		for _, p in r.players do
			eq(r.out.starts[p], 1) -- ninguém pulado nem salvo duas vezes
			local res = r.out.results[p]
			truthy(res ~= nil, "jogador sem resultado")
			truthy(res.at <= r.deadline, "save terminou depois do prazo")
			local rec = r.store.data["Player_" .. p.UserId]
			if res.ok then
				okCount += 1
				eq(failsByUser[p.UserId], nil)
				eq(rec.Coins, p.coins)
				eq(rec.SessionJobId, nil) -- trava liberada
			else
				failCount += 1
				eq(failsByUser[p.UserId], 1) -- exatamente um save_failed
				eq(rec.Coins, 0) -- nada parcial
				eq(rec.SessionJobId, JOB) -- não gravou; trava expira sozinha (LOCK_TIMEOUT)
			end
		end
		return okCount, failCount
	end

	describe("BindToClose com 60 jogadores", function()
		it("orçamento baixo (5 + 2/s): cada um salva ou registra um save_failed antes de 25s", function()
			local r = closeAll(60, 5, 2, 10, 0.2)
			local okCount, failCount = checkInvariants(r)
			eq(okCount + failCount, 60)
			truthy(okCount >= 40, "poucos saves com sucesso: " .. okCount)
			truthy(failCount >= 1, "o cenário deveria esgotar o orçamento")
		end)

		it("orçamento normal (60 + 60/s): todos salvam e soltam a trava bem antes do prazo", function()
			local r = closeAll(60, 60, 60, 120, 0.2)
			local okCount = checkInvariants(r)
			eq(okCount, 60)
			truthy(r.returnedAt < 2)
		end)

		it("orçamento zerado: todos desistem pelo prazo, um save_failed cada, sem chamar atrasado", function()
			local r = closeAll(60, 0, 0, 0, 0.2)
			local okCount, failCount = checkInvariants(r)
			eq(okCount, 0)
			eq(failCount, 60)
			eq(r.store.calls, 0) -- esperou orçamento até o prazo e desistiu sem chamar
			for _, rec in r.out.records do
				eq(rec.entry.details, "reason=deadline error=error attempts=0")
			end
		end)

		it("DataStore lento (latência 0,9s) com throttling: prazo respeitado mesmo assim", function()
			local r = closeAll(60, 3, 1.5, 6, 0.9)
			local okCount, failCount = checkInvariants(r)
			eq(okCount + failCount, 60)
		end)

		it("sem consultar orçamento (429 de verdade): retry com backoff ainda fecha no prazo", function()
			local r = closeAll(60, 5, 2, 10, 0.2, true)
			local okCount, failCount = checkInvariants(r)
			eq(okCount + failCount, 60)
			truthy(r.store.throttled > 0)
			truthy(failCount >= 1)
		end)

		it("sem jogadores: volta na hora", function()
			local r = closeAll(0, 5, 2, 10, 0.2)
			eq(r.pending, 0)
			eq(r.returnedAt, 0)
		end)
	end)
end
