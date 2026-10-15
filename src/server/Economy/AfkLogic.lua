-- Regras puras de AFK, testadas com lune em tests/.
-- Posições são qualquer valor com X, Y, Z (Vector3 no Roblox, tabela nos testes).
local AfkLogic = {}

function AfkLogic.New(now)
	return { lastActive = now, anchor = nil }
end

local function distance(a, b)
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Atividade observada pelo servidor (remote aceito, compra, emprego).
function AfkLogic.MarkActive(s, now)
	if now > s.lastActive then
		s.lastActive = now
	end
end

-- Nova âncora sem contar como atividade (respawn, teleporte feito pelo servidor).
function AfkLogic.Reanchor(s, pos)
	s.anchor = pos
end

-- Amostra de posição. Compara com a âncora (não com a amostra anterior), então tremidas
-- pequenas não somam, mas andar devagar acaba passando do limite.
-- Sem personagem (pos nil): nada muda, o tempo segue correndo.
function AfkLogic.Observe(s, pos, now, cfg)
	if pos == nil then
		return false
	end
	if s.anchor == nil then
		s.anchor = pos
		return false
	end
	if distance(pos, s.anchor) > cfg.MOVE_THRESHOLD then
		s.anchor = pos
		AfkLogic.MarkActive(s, now)
		return true
	end
	return false
end

-- Sinal auxiliar (Player.Idled): só pode tornar o jogador mais inativo, nunca mais ativo.
function AfkLogic.MarkIdled(s, now, idleSeconds)
	if type(idleSeconds) ~= "number" or idleSeconds ~= idleSeconds or idleSeconds <= 0 then
		return
	end
	s.lastActive = math.min(s.lastActive, now - idleSeconds)
end

-- AFK a partir de exatamente TIMEOUT segundos sem atividade.
function AfkLogic.IsAfk(s, now, cfg)
	return now - s.lastActive >= cfg.TIMEOUT
end

return AfkLogic
