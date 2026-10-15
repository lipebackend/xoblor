-- Benchmark de carga (lune): custo por tick do servidor com N jogadores simulados.
-- Uso: lune run bench/run.luau [jogadores] [ticks] [flags]   (ou ./setup.sh bench ...)
-- Flags (modo CI, ver docs/BENCH.md):
--   --ci                  sai com código != 0 se um limite estourar e imprime linhas BENCH_RESULT (JSON)
--   --p95-ms=X            limite de p95 por cenário (padrão 1); --no-p95 desliga essa checagem
--   --stagger-max-ms=X    limite do max no cenário de autosave escalonado (padrão: sem checagem)
--   --only-stagger        roda só o cenário escalonado (mais rápido para a checagem de max)
-- Códigos de saída com --ci: 0 ok, 1 p95 estourou, 2 max do escalonado estourou,
--   3 checagem do escalonado pedida mas AutosaveSchedule ausente.
-- Mede só as regras puras (MoveLogic, RemoteGuard, SecurityLogic, ProfileLogic) e um
-- DataStore falso; APIs do Roblox (Vector3, Players, rede, DataStore real) não entram.
local process = require("@lune/process")
local serde = require("@lune/serde")

local Move = require("../src/server/Economy/MoveLogic")
local Guard = require("../src/server/Economy/RemoteGuard")
local Sec = require("../src/server/Economy/SecurityLogic")
local Profile = require("../src/server/Economy/ProfileLogic")
-- AutosaveSchedule vem do #43; sem ele, o cenário escalonado é pulado.
local okSchedule, Schedule = pcall(require, "../src/server/Economy/AutosaveSchedule")
if not okSchedule then
	Schedule = nil
end

local positional, flags = {}, {}
for _, a in process.args do
	local k, v = a:match("^%-%-([%w%-]+)=(.*)$")
	if k then
		flags[k] = v
	elseif a:sub(1, 2) == "--" then
		flags[a:sub(3)] = true
	else
		table.insert(positional, a)
	end
end
local CI = flags.ci == true or process.env.XOBLOR_BENCH_CI == "1"
local P95_MS = tonumber(flags["p95-ms"]) or 1
local CHECK_P95 = flags["no-p95"] == nil
local STAGGER_MAX_MS = tonumber(flags["stagger-max-ms"])
local ONLY_STAGGER = flags["only-stagger"] ~= nil

local PLAYERS = tonumber(positional[1]) or 30
local TICKS = tonumber(positional[2]) or 2000
local WARMUP = 200
local TICK_DT = Move.Config.SAMPLE_INTERVAL -- 1 tick = 0,5 s de jogo (uma amostra de movimento)
local AUTOSAVE_EVERY = math.floor(60 / TICK_DT) -- autosave de todos a cada 60 s (DataStoreHandler)
local BUDGET_MS = P95_MS

local V = Guard.V
-- Mesmos schemas de RemoteUtil.REMOTES (amostra representativa).
local REMOTES = {
	{ name = "BankDeposit", interval = 0.5, burst = 2, args = { V.Money }, weight = 3 },
	{ name = "Pix", interval = 1, burst = 2, args = { V.UserId, V.Money }, weight = 2 },
	{ name = "RobAttempt", interval = 0.5, burst = 1, args = { V.UserId }, weight = 1 },
	{
		name = "HouseAction",
		interval = 0.5,
		burst = 2,
		args = { V.OneOf("list", "rent", "buy", "invite", "uninvite"), V.Optional(V.Id), V.Optional(V.UserId) },
		weight = 2,
	},
	{ name = "Arrest", interval = 0.5, burst = 1, args = { V.UserId }, weight = 1 },
}
local GLOBAL = { interval = 0.1, burst = 20 }

-- Random do Roblox não existe no lune: wrapper com a mesma interface sobre math.random.
math.randomseed(42)
local rng = {}
function rng:NextNumber(a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * math.random()
end
function rng:NextInteger(a, b)
	return math.random(a, b)
end

local function newWorld()
	local w = { players = {}, counters = {}, throttle = {}, store = {}, now = 1000 }
	for i = 1, PLAYERS do
		w.players[i] = {
			id = 1_000_000 + i,
			move = Move.New(),
			pos = { X = rng:NextNumber(-500, 500), Y = 5, Z = rng:NextNumber(-500, 500) },
			buckets = {},
			global = nil,
			abuser = i <= 2, -- 2 jogadores spammando remotes / payload inválido
			teleporter = i == 3, -- 1 jogador teleportando de vez em quando
			coins = rng:NextInteger(0, 1e6),
			extra = { Job = "Taxi", Hunger = 80, Downed = false, Inventory = { "Pizza", "Phone" } },
			jail = { Remaining = 0, Reason = "" },
		}
	end
	return w
end

local function record(w, p, event, context, details)
	Sec.Count(w.counters, p.id, event)
	if Sec.ShouldEmit(w.throttle, p.id, event, w.now, 10) then
		local line = Sec.Format(Sec.Entry(event, p.id, context, details, w.now))
		w.lines += 1
		w.bytes += #line
	end
end

local function callRemote(w, p, spec, ...)
	local ok
	ok, p.global = Guard.Take(p.global, w.now, GLOBAL.interval, GLOBAL.burst)
	local ok2
	ok2, p.buckets[spec.name] = Guard.Take(p.buckets[spec.name], w.now, spec.interval, spec.burst)
	if not (ok and ok2) then
		record(w, p, "rate_limit", spec.name, "")
		return
	end
	local valid, bad = Guard.Check(spec.args, select("#", ...), { ... })
	if not valid then
		record(w, p, "invalid_payload", spec.name, ("argumento %d inválido [strike 1]"):format(bad))
	end
end

local function pickRemote()
	local total = 0
	for _, r in REMOTES do
		total += r.weight
	end
	local x = rng:NextNumber(0, total)
	for _, r in REMOTES do
		x -= r.weight
		if x <= 0 then
			return r
		end
	end
	return REMOTES[1]
end

local function argsFor(w, spec, bad)
	local other = w.players[rng:NextInteger(1, PLAYERS)].id
	if bad then
		return 0 / 0, "x\u{2028}y" -- NaN e lixo
	end
	if spec.name == "BankDeposit" then
		return rng:NextInteger(1, 1000)
	elseif spec.name == "Pix" then
		return other, rng:NextInteger(1, 500)
	elseif spec.name == "HouseAction" then
		return "invite", "House_" .. rng:NextInteger(1, 20), other
	end
	return other
end

local function sampleAll(w)
	for _, p in w.players do
		local pos = p.pos
		local np = { X = pos.X + rng:NextNumber(-6, 6), Y = pos.Y, Z = pos.Z + rng:NextNumber(-6, 6) }
		if p.teleporter and rng:NextNumber() < 0.05 then
			np.X += 400
		end
		p.pos = np
		if Move.Sample(p.move, np, w.now, Move.MaxSpeed(16, nil)) == "jump" then
			record(w, p, "movement_jump", "Movement", ("jumps=%d block=%ds"):format(p.move.Jumps, 5))
		end
	end
end

local function remotesAll(w)
	for _, p in w.players do
		-- jogador normal: ~1 chamada por tick (2/s); abusador: 15 por tick, 1/3 inválidas
		local n = p.abuser and 15 or (rng:NextNumber() < 0.6 and 1 or 2)
		for _ = 1, n do
			local spec = pickRemote()
			callRemote(w, p, spec, argsFor(w, spec, p.abuser and rng:NextNumber() < 0.33))
		end
		Move.IsBlocked(p.move, w.now) -- ações físicas consultam o bloqueio
	end
end

-- DataStore falso: UpdateAsync aplica a transformação e serializa (JSON) como o Roblox faria.
local function updateAsync(store, key, transform)
	local old = store[key] and serde.decode("json", store[key]) or nil
	local new = transform(old)
	if new ~= nil then
		store[key] = serde.encode("json", new)
	end
end

local function autosaveAll(w)
	for _, p in w.players do
		updateAsync(w.store, "Player_" .. p.id, function(old)
			return Profile.BuildSave(old, "job-bench", w.now, p.coins, p.extra, p.jail, false)
		end)
	end
end

local function loadAll(w)
	for _, p in w.players do
		updateAsync(w.store, "Player_" .. p.id, function(old)
			if Profile.LockDecision(old, "job-bench", w.now) == "locked" then
				return nil
			end
			local data = Profile.Migrate(old, w.now)
			data.SessionJobId, data.SessionTime = "job-bench", w.now
			return data
		end)
	end
end

local function stats(xs)
	table.sort(xs)
	local n = #xs
	local sum = 0
	for _, x in xs do
		sum += x
	end
	local function q(f)
		return xs[math.clamp(math.ceil(f * n), 1, n)]
	end
	return { n = n, mean = sum / n, median = q(0.5), p95 = q(0.95), p99 = q(0.99), max = xs[n] }
end

local function bench(label, w, fn)
	local times = {}
	for t = 1, WARMUP + TICKS do
		w.now += TICK_DT
		local t0 = os.clock()
		fn(w, t)
		local dt = (os.clock() - t0) * 1000
		if t > WARMUP then
			table.insert(times, dt)
		end
	end
	return label, stats(times)
end

local results = {}
local function run(label, fn)
	if ONLY_STAGGER and not label:find("escalonado", 1, true) then
		return
	end
	local w = newWorld()
	w.lines, w.bytes = 0, 0
	loadAll(w)
	local l, s = bench(label, w, fn)
	s.lines = w.lines
	table.insert(results, { l, s })
end

run("movimento (Sample)", function(w)
	sampleAll(w)
end)
run("remotes (rate limit + schema + log)", function(w)
	remotesAll(w)
end)
run("autosave (BuildSave + JSON, todos de uma vez)", function(w)
	autosaveAll(w)
end)
run("autosave só lógica (BuildSave, sem JSON)", function(w)
	for _, p in w.players do
		Profile.BuildSave(nil, "job-bench", w.now, p.coins, p.extra, p.jail, false)
	end
end)
run("tick normal (movimento + remotes)", function(w)
	sampleAll(w)
	remotesAll(w)
end)
run("tick com autosave (pior caso)", function(w)
	sampleAll(w)
	remotesAll(w)
	autosaveAll(w)
end)
-- Antes x depois do #43, com a cadência real (cada jogador salva a cada 60 s = 120 ticks).
-- Os ticks com save aparecem no p99/max; por isso a coluna "max" é a que importa aqui.
run("autosave 60s: todos no mesmo tick (antes)", function(w, t)
	sampleAll(w)
	remotesAll(w)
	if t % AUTOSAVE_EVERY == 0 then
		autosaveAll(w)
	end
end)
if Schedule then
	local function saveOne(w, p)
		updateAsync(w.store, "Player_" .. p.id, function(old)
			return Profile.BuildSave(old, "job-bench", w.now, p.coins, p.extra, p.jail, false)
		end)
	end
	run("autosave 60s: escalonado (AutosaveSchedule)", function(w)
		if not w.schedule then
			w.schedule = Schedule.New(60)
			for _, p in w.players do
				Schedule.Add(w.schedule, p, w.now)
			end
		end
		sampleAll(w)
		remotesAll(w)
		for _, p in Schedule.Due(w.schedule, w.now) do
			saveOne(w, p)
		end
	end)
else
	print("(AutosaveSchedule ausente: cenário escalonado pulado; precisa do #43)")
end

print(
	("xoblor bench: %d jogadores, %d ticks (+%d warmup), tick = %.1fs de jogo, autosave a cada %d ticks"):format(
		PLAYERS,
		TICKS,
		WARMUP,
		TICK_DT,
		AUTOSAVE_EVERY
	)
)
print(("%-46s %9s %9s %9s %9s %9s"):format("cenário (ms/tick)", "mediana", "p95", "p99", "max", "média"))
local over = false
for _, r in results do
	local l, s = r[1], r[2]
	print(("%-46s %9.4f %9.4f %9.4f %9.4f %9.4f"):format(l, s.median, s.p95, s.p99, s.max, s.mean))
	if CHECK_P95 and s.p95 > BUDGET_MS then
		over = true
	end
	if CI then
		print("BENCH_RESULT " .. serde.encode("json", {
			scenario = l,
			players = PLAYERS,
			ticks = TICKS,
			median = s.median,
			p95 = s.p95,
			p99 = s.p99,
			max = s.max,
		}))
	end
end
print(
	over and ("ATENÇÃO: algum cenário passou de %d ms no p95"):format(BUDGET_MS)
		or ("OK: todos abaixo de %d ms no p95"):format(BUDGET_MS)
)

local staggerLabel = "autosave 60s: escalonado (AutosaveSchedule)"
local code = 0
if STAGGER_MAX_MS then
	local found
	for _, r in results do
		if r[1] == staggerLabel then
			found = r[2]
		end
	end
	if not found then
		print("FALHA: --stagger-max-ms pedido, mas AutosaveSchedule não existe (cenário escalonado não rodou)")
		code = 3
	elseif found.max > STAGGER_MAX_MS then
		print(("FALHA: max do autosave escalonado = %.4f ms > %.4f ms"):format(found.max, STAGGER_MAX_MS))
		code = 2
	else
		print(("OK: max do autosave escalonado = %.4f ms <= %.4f ms"):format(found.max, STAGGER_MAX_MS))
	end
end
if CHECK_P95 and over and code == 0 then
	code = 1
end
if CI then
	process.exit(code)
end
