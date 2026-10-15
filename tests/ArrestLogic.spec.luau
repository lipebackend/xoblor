local A = require("../src/server/Economy/ArrestLogic")

return function(T)
	local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy
	local C = A.Config

	describe("ArrestLogic.Config (padrões)", function()
		it("valores combinados", function()
			eq(C.SENTENCE_BASE, 60)
			eq(C.SENTENCE_PER_100, 1)
			eq(C.SENTENCE_MAX, 180)
			eq(C.FINE_PCT, 20)
			eq(C.VICTIM_REFUND, false)
			truthy(C.BLOCKED.Rob and C.BLOCKED.Buy and C.BLOCKED.Pix and C.BLOCKED.Job)
		end)
	end)

	describe("ArrestLogic.Sentence", function()
		it("base sem roubo", function()
			eq(A.Sentence(0), 60)
			eq(A.Sentence(nil), 60)
			eq(A.Sentence(99), 60)
		end)
		it("+1s por R$100", function()
			eq(A.Sentence(100), 61)
			eq(A.Sentence(2000), 80)
		end)
		it("teto de 180s", function()
			eq(A.Sentence(12000), 180)
			eq(A.Sentence(1e12), 180)
		end)
		it("config customizada", function()
			eq(A.Sentence(500, { SENTENCE_BASE = 10, SENTENCE_PER_100 = 2, SENTENCE_MAX = 15 }), 15)
		end)
		it("lixo vira base", function()
			eq(A.Sentence(-500), 60)
			eq(A.Sentence(0 / 0), 60)
		end)
	end)

	describe("ArrestLogic.Fine", function()
		it("20% truncado", function()
			eq(A.Fine(1000), 200)
			eq(A.Fine(99), 19)
			eq(A.Fine(4), 0)
			eq(A.Fine(0), 0)
		end)
		it("nunca passa da carteira", function()
			for w = 0, 300, 13 do
				truthy(A.Fine(w) <= w)
			end
			eq(A.Fine(10, { FINE_PCT = 150 }), 10)
		end)
	end)

	describe("ArrestLogic.CanArrest", function()
		local function base(o)
			local a = {
				CopIsPolice = true,
				CopJailed = false,
				CopCooldownUntil = 0,
				TargetIsPolice = false,
				TargetWanted = true,
				TargetJailed = false,
				Distance = 5,
				Now = 1000,
			}
			for k, v in pairs(o or {}) do
				a[k] = v
			end
			return a
		end
		it("caso válido", function()
			eq(A.CanArrest(base()), nil)
		end)
		it("só polícia prende", function()
			eq(A.CanArrest(base({ CopIsPolice = false })), "NotPolice")
		end)
		it("policial preso não prende", function()
			eq(A.CanArrest(base({ CopJailed = true })), "Jailed")
		end)
		it("cooldown do policial", function()
			eq(A.CanArrest(base({ CopCooldownUntil = 1001 })), "Cooldown")
		end)
		it("alvo já preso", function()
			eq(A.CanArrest(base({ TargetJailed = true })), "AlreadyJailed")
		end)
		it("alvo não procurado ou policial", function()
			eq(A.CanArrest(base({ TargetWanted = false })), "NotWanted")
			eq(A.CanArrest(base({ TargetIsPolice = true })), "NotWanted")
		end)
		it("distância", function()
			eq(A.CanArrest(base({ Distance = C.ARREST_DISTANCE })), nil)
			eq(A.CanArrest(base({ Distance = C.ARREST_DISTANCE + 0.1 })), "TooFar")
			eq(A.CanArrest(base({ Distance = 0 / 0 })), "TooFar")
		end)
	end)

	describe("ArrestLogic.Jail (formato salvo)", function()
		it("ausente, corrompido ou Remaining 0 = solto", function()
			eq(A.IsJailed(nil), false)
			for _, j in { "x", {}, { Remaining = 0 }, { Remaining = "abc" }, { Remaining = -5 }, { Remaining = 0 / 0 } } do
				eq(A.IsJailed(j), false)
				eq(A.Remaining(j), 0)
			end
		end)
		it("campo legado EndsAt é ignorado (solto)", function()
			eq(A.IsJailed({ EndsAt = 9e9, Reason = "assalto" }), false)
			eq(A.Remaining({ EndsAt = 9e9, Remaining = 30 }), 30)
		end)
		it("NewJail", function()
			local j = A.NewJail(61, "assalto")
			eq(j.Remaining, 61)
			eq(j.Reason, "assalto")
			eq(A.NewJail(10).Reason, "")
		end)
	end)

	describe("ArrestLogic.Tick (só online)", function()
		it("desconta e libera em 0", function()
			local j, done = A.Tick(A.NewJail(3, "assalto"), 1)
			eq(A.Remaining(j), 2)
			eq(j.Reason, "assalto")
			eq(done, false)
			j, done = A.Tick(j, 2.5)
			eq(A.Remaining(j), 0)
			eq(done, true)
		end)
		it("solto continua solto (não 'solta' de novo)", function()
			local j, done = A.Tick(nil, 1)
			eq(A.Remaining(j), 0)
			eq(done, false)
		end)
		it("sair e voltar: o restante salvo é o que falta", function()
			local j = A.NewJail(60, "assalto")
			for _ = 1, 20 do
				j = A.Tick(j, 1) -- 20s online
			end
			-- saiu: o perfil salva a tabela como está (sem Tick offline)
			local saved = { Remaining = j.Remaining, Reason = j.Reason }
			-- voltou (horas depois): mesma pena restante
			eq(A.Remaining(saved), 40)
			eq(A.IsJailed(saved), true)
		end)
		it("fração arredonda para cima ao ler", function()
			local j = A.Tick(A.NewJail(10), 0.4)
			eq(A.Remaining(j), 10)
			eq(A.IsJailed(A.Tick(A.NewJail(1), 0.9)), true)
		end)
	end)

	describe("ArrestLogic.Allowed", function()
		it("preso bloqueado no que está em BLOCKED", function()
			for _, act in { "Rob", "Buy", "Pix", "Job" } do
				eq(A.Allowed(act, true), false)
				eq(A.Allowed(act, false), true)
			end
			eq(A.Allowed("Rob", true, { BLOCKED = {} }), true)
		end)
	end)

	describe("ArrestLogic.RefundPlan", function()
		local victims = { { u = 1, v = 300 }, { u = 2, v = 500 } }
		it("desligado por padrão", function()
			local plan, total = A.RefundPlan(victims, 1e6)
			eq(#plan, 0)
			eq(total, 0)
		end)
		it("ligado: em ordem, limitado ao disponível", function()
			local cfg = { VICTIM_REFUND = true }
			local plan, total = A.RefundPlan(victims, 600, cfg)
			eq(#plan, 2)
			eq(plan[1].v, 300)
			eq(plan[2].v, 300)
			eq(total, 600)
			plan, total = A.RefundPlan(victims, 0, cfg)
			eq(total, 0)
		end)
	end)
end
