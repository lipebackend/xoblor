-- 100 chamadas em 1 s (relógio falso) por remote econômico, pelo caminho real
-- (RemoteGuard.Invoker + specs de RemoteSpecs) com uma economia falsa.
local G = require("../src/server/Economy/RemoteGuard")
local Specs = require("../src/server/Economy/RemoteSpecs")
local SL = require("../src/server/Economy/SecurityLogic")
local AdminConfig = require("../src/server/Economy/AdminConfig")

local REMOTES = Specs.Build(G.V)
local CALLS, TICK = 100, 0.01 -- t = 0.00 .. 0.99
local PLAYER = { UserId = 1 } -- mesma instância em todas as chamadas, como um Player real

-- Referência em inteiros (centésimos de segundo e de token): sem erro de ponto flutuante.
local function reference(spec)
	local function bucket(interval, burst)
		return { tok = burst * 100, cap = burst * 100, per = 100 // math.round(interval * 100) }
	end
	local g, r = bucket(Specs.GLOBAL.interval, Specs.GLOBAL.burst), bucket(spec.interval, spec.burst)
	local accepted = 0
	for i = 0, CALLS - 1 do
		for _, b in { g, r } do
			if i > 0 then
				b.tok = math.min(b.cap, b.tok + b.per)
			end
		end
		if g.tok >= 100 then
			g.tok -= 100
			if r.tok >= 100 then
				r.tok -= 100
				accepted += 1
			end
		end
	end
	return accepted
end

local function harness(name, handler)
	local now = 0
	local clock = function()
		return now
	end
	local counters, throttle, lines, flags = {}, {}, {}, 0
	local spec = REMOTES[name]
	local invoke = G.Invoker(name, spec.args, handler, {
		global = G.Limiter(Specs.GLOBAL.interval, Specs.GLOBAL.burst, clock),
		rate = G.Limiter(spec.interval, spec.burst, clock),
		-- mesmo corpo de SecurityLog.Record, com relógio falso
		record = function(player, event, context, details)
			local n = SL.Count(counters, player.UserId, event)
			if SL.ShouldEmit(throttle, player.UserId, event, now, AdminConfig.LOG_THROTTLE) then
				table.insert(lines, SL.Format(SL.Entry(event, player.UserId, context, details, now)))
			end
			return n
		end,
		flag = function()
			flags += 1
		end,
		log = function() end,
	})
	local h = { spec = spec, lines = lines, counters = counters }
	function h.fire(start, ...)
		local accepted = 0
		for i = 0, CALLS - 1 do
			now = start + i * TICK
			local ok, err = invoke(PLAYER, ...)
			if ok then
				accepted += 1
			else
				assert(err == "RateLimited", "erro inesperado: " .. tostring(err))
			end
		end
		return accepted
	end
	function h.flags()
		return flags
	end
	return h
end

return function(T)
	local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

	-- economia falsa: carteira/banco por jogador
	local function econ()
		local e = { [1] = { wallet = 10_000, bank = 10_000, items = 0 }, [2] = { wallet = 0, bank = 0, items = 0 } }
		function e.move(uid, from, to, amt)
			local a = e[uid]
			if a[from] < amt then
				return false, "Insufficient"
			end
			a[from] -= amt
			a[to] += amt
			return true
		end
		return e
	end

	local function checkLog(h, accepted)
		local rejected = CALLS - accepted
		eq(h.counters[1].rate_limit, rejected) -- contador soma tudo
		eq(#h.lines, 1) -- console: 1 linha em 1 s (throttle de 10 s)
		truthy(h.lines[1]:find("event=rate_limit", 1, true))
		eq(h.flags(), 0)
	end

	local function depositLike(name, from, to, ...)
		local args = table.pack(...)
		it(name .. ": só o limite passa, wallet+bank fecha", function()
			local e = econ()
			local h = harness(name, function(player, a, b)
				local amt = b or a
				return e.move(player.UserId, from, to, amt)
			end)
			local accepted = h.fire(0, table.unpack(args, 1, args.n))
			eq(accepted, reference(h.spec))
			truthy(accepted <= h.spec.burst + math.floor((CALLS - 1) * TICK / h.spec.interval))
			local amt = args[args.n]
			eq(e[1].wallet + e[1].bank, 20_000)
			eq(e[1][to], 10_000 + accepted * amt)
			checkLog(h, accepted)
			-- depois da janela de 10 s volta a emitir uma linha, contador continua somando
			local again = h.fire(20, table.unpack(args, 1, args.n))
			eq(#h.lines, 2)
			eq(h.counters[1].rate_limit, 2 * CALLS - accepted - again)
		end)
	end

	describe("Rate limit dos remotes econômicos (100 chamadas em 1 s)", function()
		depositLike("BankDeposit", "wallet", "bank", 10)
		depositLike("BankWithdraw", "bank", "wallet", 10)
		depositLike("AtmAction", "wallet", "bank", "deposit", 10)

		it("Pix: só o limite passa, remetente+destinatário fecha", function()
			local e = econ()
			local h = harness("Pix", function(player, target, amt)
				local s, r = e[player.UserId], e[target]
				if s.bank < amt then
					return false, "Insufficient"
				end
				s.bank -= amt
				r.bank += amt
				return true
			end)
			local accepted = h.fire(0, 2, 50)
			eq(accepted, reference(h.spec))
			eq(e[1].bank + e[2].bank, 10_000)
			eq(e[2].bank, accepted * 50)
			checkLog(h, accepted)
		end)

		for _, name in { "RequestPurchase", "StoreBuy" } do
			it(name .. ": só o limite passa, débito = compras aceitas", function()
				local e = econ()
				local h = harness(name, function(player)
					local a = e[player.UserId]
					a.wallet -= 25
					a.items += 1
					return true
				end)
				local accepted = h.fire(0, "car_basic")
				eq(accepted, reference(h.spec))
				eq(e[1].items, accepted)
				eq(e[1].wallet, 10_000 - 25 * accepted)
				checkLog(h, accepted)
			end)
		end

		it("limites esperados (100 chamadas/1 s)", function()
			eq(reference(REMOTES.BankDeposit), 3)
			eq(reference(REMOTES.BankWithdraw), 3)
			eq(reference(REMOTES.AtmAction), 3)
			eq(reference(REMOTES.Pix), 2)
			eq(reference(REMOTES.RequestPurchase), 3)
			eq(reference(REMOTES.StoreBuy), 3)
		end)
	end)
end
