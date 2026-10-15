local S = require("../src/server/Economy/AutosaveSchedule")

return function(T)
	local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

	-- simula `seconds` s em passos de `step`, contando saves por chave e por segundo
	local function simulate(s, from, seconds, step)
		local perKey, perSecond, times = {}, {}, {}
		local t = from
		while t < from + seconds do
			t += step
			for _, k in S.Due(s, t) do
				perKey[k] = (perKey[k] or 0) + 1
				local sec = math.floor(t)
				perSecond[sec] = (perSecond[sec] or 0) + 1
				times[k] = times[k] or {}
				table.insert(times[k], t)
			end
		end
		return perKey, perSecond, times
	end

	describe("AutosaveSchedule", function()
		it("fases ficam em [0, interval)", function()
			for k = 0, 500 do
				local p = S.Phase(k, 60)
				truthy(p >= 0 and p < 60)
			end
		end)

		it("30 jogadores entrando juntos se espalham pelo intervalo", function()
			local s = S.New(60)
			for i = 1, 30 do
				S.Add(s, "p" .. i, 0)
			end
			local _, perSecond = simulate(s, 0, 60, 1)
			local maxBurst = 0
			for _, n in perSecond do
				maxBurst = math.max(maxBurst, n)
			end
			truthy(maxBurst <= 3) -- antes: 30 no mesmo tick
			-- cada sexto do intervalo (10s) recebe entre 3 e 7 saves
			local buckets = {}
			for sec, n in perSecond do
				local b = math.floor((sec % 60) / 10)
				buckets[b] = (buckets[b] or 0) + n
			end
			for b = 0, 5 do
				truthy((buckets[b] or 0) >= 3 and (buckets[b] or 0) <= 7)
			end
		end)

		it("cada jogador salva exatamente a cada interval (sem save duplo)", function()
			local s = S.New(60)
			for i = 1, 10 do
				S.Add(s, i, 0)
			end
			local perKey, _, times = simulate(s, 0, 600, 0.25)
			for i = 1, 10 do
				eq(perKey[i], 10)
				for j = 2, #times[i] do
					local gap = times[i][j] - times[i][j - 1]
					truthy(math.abs(gap - 60) < 0.26)
				end
			end
		end)

		it("primeiro save entre MIN_FIRST e interval + MIN_FIRST depois do load", function()
			local s = S.New(60)
			for i = 1, 100 do
				local now = i * 7.3
				local nextAt = S.Add(s, i, now)
				truthy(nextAt - now >= S.MIN_FIRST)
				truthy(nextAt - now <= 60 + S.MIN_FIRST)
			end
		end)

		it("Add repetido é idempotente", function()
			local s = S.New(60)
			local a = S.Add(s, "x", 10)
			eq(S.Add(s, "x", 30), a)
			eq(s.seq, 1)
		end)

		it("join/leave: quem saiu não salva mais; quem volta é reagendado", function()
			local s = S.New(60)
			S.Add(s, "a", 0)
			S.Add(s, "b", 0)
			S.Remove(s, "a")
			eq(S.NextAt(s, "a"), nil)
			local perKey = simulate(s, 0, 120, 1)
			eq(perKey.a, nil)
			eq(perKey.b, 2)
			S.Add(s, "a", 120)
			truthy(S.NextAt(s, "a") > 120)
		end)

		it("servidor travado não acumula saves (uma vez por chamada)", function()
			local s = S.New(60)
			S.Add(s, "a", 0)
			local first = S.NextAt(s, "a")
			eq(#S.Due(s, first + 600), 1)
			eq(#S.Due(s, first + 600), 0)
			truthy(S.NextAt(s, "a") > first + 600)
			truthy(S.NextAt(s, "a") <= first + 660)
		end)

		it("UserIds negativos do Studio (e chaves numéricas) funcionam", function()
			local s = S.New(60)
			for _, id in { -1, -2, -3, 123 } do
				S.Add(s, id, 0)
			end
			local perKey = simulate(s, 0, 60, 0.5)
			for _, id in { -1, -2, -3, 123 } do
				eq(perKey[id], 1)
			end
		end)

		it("interval inválido é recusado", function()
			eq(pcall(S.New, 0), false)
			eq(pcall(S.New, 0 / 0), false)
		end)
	end)
end
