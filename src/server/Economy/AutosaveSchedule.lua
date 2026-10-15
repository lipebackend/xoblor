-- Agenda do autosave escalonado (regras puras, testadas com lune em tests/).
-- Em vez de salvar todos no mesmo tick a cada `interval` s, cada jogador recebe uma fase
-- própria dentro do intervalo. A fase vem da ordem de entrada (sequência de Weyl com a razão
-- áurea): para qualquer número de jogadores, as fases ficam bem espalhadas, sem depender do
-- UserId (que pode ser negativo no Studio). Cada jogador continua salvando a cada `interval` s.
local AutosaveSchedule = {}

local PHI = (math.sqrt(5) - 1) / 2 -- 0,618...
AutosaveSchedule.MIN_FIRST = 1 -- primeiro save nunca no mesmo segundo do load

-- s = { interval, seq, entries = { [key] = { phase, nextAt } } }
function AutosaveSchedule.New(interval)
	assert(type(interval) == "number" and interval > 0, "interval inválido")
	return { interval = interval, seq = 0, entries = {} }
end

-- Fase da k-ésima entrada (k >= 0), em [0, interval).
function AutosaveSchedule.Phase(k, interval)
	return ((k * PHI) % 1) * interval
end

-- Registra `key` (o Player no jogo) em `now`. Idempotente: registrar de novo não muda a agenda.
-- O primeiro save cai no próximo instante com a fase do jogador, a pelo menos MIN_FIRST s.
function AutosaveSchedule.Add(s, key, now)
	local e = s.entries[key]
	if e then
		return e.nextAt
	end
	local phase = AutosaveSchedule.Phase(s.seq, s.interval)
	s.seq += 1
	local nextAt = now + ((phase - now) % s.interval)
	if nextAt - now < AutosaveSchedule.MIN_FIRST then
		nextAt += s.interval
	end
	s.entries[key] = { phase = phase, nextAt = nextAt }
	return nextAt
end

function AutosaveSchedule.Remove(s, key)
	s.entries[key] = nil
end

-- Chaves com save vencido em `now`. Cada uma aparece no máximo uma vez por chamada, e o
-- próximo save avança em múltiplos de `interval` (se o servidor travou, não acumula saves).
function AutosaveSchedule.Due(s, now)
	local out = {}
	for key, e in s.entries do
		if e.nextAt <= now then
			table.insert(out, key)
			local behind = math.floor((now - e.nextAt) / s.interval) + 1
			e.nextAt += behind * s.interval
		end
	end
	return out
end

function AutosaveSchedule.NextAt(s, key)
	local e = s.entries[key]
	return e and e.nextAt or nil
end

return AutosaveSchedule
