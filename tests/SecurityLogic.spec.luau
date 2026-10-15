local S = require("../src/server/Economy/SecurityLogic")

return function(T)
	local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

	describe("SecurityLogic.Entry/Format", function()
		it("linha com campos em ordem fixa", function()
			local e = S.Entry("rate_limit", 42, "Pix", "x", 1700000000)
			eq(S.Format(e), '[Security] event=rate_limit userId=42 context="Pix" details="x" ts=1700000000')
		end)
		it("quebra de linha e aspas não quebram o formato", function()
			local line = S.Format(S.Entry("flag", 1, 'a"b', "linha1\nlinha2", 0))
			eq(line:find("\n"), nil)
			truthy(line:find('context="a\'b"', 1, true) ~= nil)
		end)
		it("campos ausentes ou lixo viram vazio/0", function()
			local e = S.Entry("flag", "x", nil, nil, nil)
			eq(e.userId, 0)
			eq(e.context, "")
			eq(e.timestamp, 0)
		end)
		it("details longo é cortado", function()
			local e = S.Entry("flag", 1, "", string.rep("a", 500), 0)
			truthy(#e.details < 220)
		end)
		it("tipos de evento do jogo estão registrados", function()
			for _, k in
				{
					"rate_limit",
					"invalid_payload",
					"movement_jump",
					"session_lock_lost",
					"flag",
					"admin_denied",
					"kick",
				}
			do
				eq(S.EVENTS[k], true, k)
			end
		end)
	end)

	describe("SecurityLogic contadores", function()
		it("soma por jogador e por tipo", function()
			local c = {}
			eq(S.Count(c, 1, "rate_limit"), 1)
			eq(S.Count(c, 1, "rate_limit"), 2)
			eq(S.Count(c, 1, "flag"), 1)
			eq(S.Count(c, 2, "rate_limit"), 1)
			local snap = S.Snapshot(c, 1)
			eq(snap.rate_limit, 2)
			eq(snap.flag, 1)
		end)
		it("snapshot é cópia", function()
			local c = {}
			S.Count(c, 1, "flag")
			local snap = S.Snapshot(c, 1)
			snap.flag = 99
			eq(S.Snapshot(c, 1).flag, 1)
		end)
		it("limpa ao sair; jogador sem eventos dá tabela vazia", function()
			local c = {}
			S.Count(c, 1, "flag")
			S.Clear(c, 1)
			eq(next(S.Snapshot(c, 1)), nil)
			eq(next(S.Snapshot(c, 77)), nil)
		end)
	end)

	describe("SecurityLogic.ShouldEmit (throttle do console)", function()
		it("primeira emite, repetição na janela não, depois da janela sim", function()
			local t = {}
			eq(S.ShouldEmit(t, 1, "rate_limit", 0, 10), true)
			eq(S.ShouldEmit(t, 1, "rate_limit", 5, 10), false)
			eq(S.ShouldEmit(t, 1, "rate_limit", 10, 10), true)
		end)
		it("jogadores e eventos diferentes são independentes", function()
			local t = {}
			S.ShouldEmit(t, 1, "rate_limit", 0, 10)
			eq(S.ShouldEmit(t, 2, "rate_limit", 0, 10), true)
			eq(S.ShouldEmit(t, 1, "flag", 0, 10), true)
		end)
	end)

	describe("SecurityLogic.IsAdmin", function()
		local list = { 111, 222 }
		it("UserId na lista", function()
			eq(S.IsAdmin(list, 111), true)
		end)
		it("fora da lista, lista vazia ou nil", function()
			eq(S.IsAdmin(list, 333), false)
			eq(S.IsAdmin({}, 111), false)
			eq(S.IsAdmin(nil, 111), false)
		end)
		it("tipos estranhos nunca são admin", function()
			eq(S.IsAdmin(list, "111"), false)
			eq(S.IsAdmin(list, 111.5), false)
			eq(S.IsAdmin(list, 0 / 0), false)
			eq(S.IsAdmin(list, -111), false)
			eq(S.IsAdmin(list, nil), false)
		end)
	end)
	describe("SecurityLogic.Strike (kick do RemoteUtil.Flag)", function()
		it("expulsa exatamente no 30º strike dentro de 60s", function()
			local st, n, kick
			for i = 1, 29 do
				st, n, kick = S.Strike(st, i, 60, 30)
				eq(kick, false)
			end
			st, n, kick = S.Strike(st, 29.5, 60, 30)
			eq(n, 30)
			eq(kick, true)
		end)
		it("janela expirada recomeça a contagem", function()
			local st = nil
			for i = 1, 29 do
				st = S.Strike(st, i * 0.1, 60, 30)
			end
			local _, n, kick = S.Strike(st, 100, 60, 30)
			eq(n, 1)
			eq(kick, false)
		end)
		it("limite de janela: 60s ainda conta, depois recomeça", function()
			local st = S.Strike(nil, 0, 60, 30)
			local _, n = S.Strike(st, 60, 60, 30)
			eq(n, 2)
			local _, n2 = S.Strike(st, 60.1, 60, 30)
			eq(n2, 1)
		end)
	end)
	describe("SecurityLogic.IsAdmin no Studio", function()
		it("negativo só conta no Studio", function()
			eq(S.IsAdmin({ -1 }, -1, true), true)
			eq(S.IsAdmin({ -1 }, -1, false), false)
			eq(S.IsAdmin({ -1 }, -1), false)
			eq(S.IsAdmin({ 111 }, 111, true), true)
		end)
		it("0, NaN, inf e frações recusados nos dois modos", function()
			for _, studio in { false, true } do
				eq(S.IsAdmin({ 0 }, 0, studio), false)
				eq(S.IsAdmin({ 1 }, 0 / 0, studio), false)
				eq(S.IsAdmin({ math.huge }, math.huge, studio), false)
				eq(S.IsAdmin({ -math.huge }, -math.huge, studio), false)
				eq(S.IsAdmin({ -1.5 }, -1.5, studio), false)
			end
		end)
	end)

	describe("SecurityLogic UTF-8 (corte e bytes inválidos)", function()
		local function valid(x)
			return utf8.len(x) ~= nil
		end
		it("não corta no meio de acento (2 bytes)", function()
			-- "aé" * n: o limite cai no meio de "é" em várias posições
			for max = 1, 12 do
				local r = S.Truncate(string.rep("aé", 10), max)
				truthy(valid(r))
				truthy(#r <= max + #"…")
			end
		end)
		it("não corta no meio de emoji (4 bytes)", function()
			local s = "x" .. string.rep("😀", 5)
			for max = 1, 20 do
				local r = S.Truncate(s, max)
				truthy(valid(r))
				truthy(r:sub(-3) == "…")
			end
			eq(S.Truncate(s, 3), "x…")
			eq(S.Truncate(s, 5), "x😀…")
		end)
		it("string curta fica intacta", function()
			eq(S.Truncate("ação 😀", 100), "ação 😀")
		end)
		it("bytes inválidos viram ?", function()
			eq(S.ValidUtf8("a" .. string.char(0xFF) .. "b"), "a?b")
			eq(S.ValidUtf8("\xC3"), "?") -- sequência truncada
			eq(S.ValidUtf8("\x80\x80ok"), "??ok")
			eq(S.ValidUtf8("ção"), "ção")
		end)
		it("Entry com lixo binário longo gera UTF-8 válido", function()
			local e = S.Entry("flag", 1, "\xE2\x80", string.rep("é\xFF😀", 100), 0)
			truthy(valid(e.details))
			truthy(valid(e.context))
			truthy(valid(S.Format(e)))
			truthy(#e.details <= 200 + #"…")
		end)
		it("corte após troca de inválidos continua em fronteira", function()
			local e = S.Entry("flag", 1, "", string.rep("\xF0", 50) .. string.rep("ã", 200), 0)
			truthy(valid(e.details))
		end)
	end)

	describe("SecurityLogic sanitizer (separadores Unicode)", function()
		it("U+2028 e U+2029 viram espaço", function()
			local e = S.Entry("flag", 1, "a\u{2028}b", "x\u{2029}y", 0)
			eq(e.context, "a b")
			eq(e.details, "x y")
			local line = S.Format(e)
			eq(line:find("\u{2028}", 1, true), nil)
			eq(line:find("\u{2029}", 1, true), nil)
		end)
		it("NEL (U+0085), \\r e \\n também", function()
			eq(S.Clean("a\u{0085}b\rc\nd", 50), "a b c d")
		end)
		it("acentos e emoji preservados", function()
			eq(S.Clean("São Paulo 😀", 50), "São Paulo 😀")
		end)
	end)
end
