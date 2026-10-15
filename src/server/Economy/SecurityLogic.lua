-- Regras puras da telemetria de segurança (formato do log, contadores, allowlist de admin),
-- testadas com lune em tests/.
local SecurityLogic = {}

-- Tipos de evento conhecidos (outros são aceitos, mas estes são os do jogo).
SecurityLogic.EVENTS = {
	rate_limit = true, -- remote recusado por rate limit
	invalid_payload = true, -- argumento inválido ou handler devolveu "Invalid"
	movement_jump = true, -- salto impossível (MovementService, #37)
	session_lock_lost = true, -- trava de sessão do DataStore tomada por outro servidor
	flag = true, -- outras suspeitas (corrida, Pix acima do limite)
	admin_denied = true, -- não-admin tentou consultar a telemetria
	kick = true, -- expulso por strikes (RemoteUtil.Flag), registrado ANTES do Kick
}

-- Strikes do RemoteUtil.Flag: janela fixa de `window` s a partir do primeiro strike.
-- Retorna o estado (novo ou o mesmo), o número de strikes na janela e se deve expulsar:
-- verdadeiro sempre que strikes >= `max` (o primeiro Kick já tira o jogador do servidor).
function SecurityLogic.Strike(state, now, window, max)
	if state == nil or now - state.since > window then
		state = { n = 0, since = now }
	end
	state.n += 1
	return state, state.n, state.n >= max
end

-- Troca bytes que não formam UTF-8 válido por "?" (nunca propaga lixo ao log).
local function validUtf8(s)
	local out = {}
	local i = 1
	while i <= #s do
		local ok, bad = utf8.len(s, i)
		if ok then
			table.insert(out, s:sub(i))
			break
		end
		table.insert(out, s:sub(i, bad - 1) .. "?")
		i = bad + 1
	end
	return table.concat(out)
end
SecurityLogic.ValidUtf8 = validUtf8

-- Corta em no máximo `max` bytes sem partir uma sequência multibyte (s já é UTF-8 válido).
local function truncate(s, max)
	if #s <= max then
		return s
	end
	local j = max
	-- recua enquanto o próximo byte for de continuação (10xxxxxx)
	while j > 0 and bit32.band(s:byte(j + 1), 0xC0) == 0x80 do
		j -= 1
	end
	return s:sub(1, j) .. "…"
end
SecurityLogic.Truncate = truncate

local function clean(v, max)
	local s = validUtf8(tostring(v == nil and "" or v))
	s = s:gsub("[%c]", " ") -- sem quebra de linha: uma entrada por linha no log
	-- separadores Unicode que também quebram linha: NEL, U+2028 e U+2029
	s = s:gsub("\u{0085}", " "):gsub("\u{2028}", " "):gsub("\u{2029}", " ")
	return truncate(s, max)
end
SecurityLogic.Clean = clean

-- Monta a entrada estruturada.
function SecurityLogic.Entry(event, userId, context, details, timestamp)
	return {
		event = clean(event, 32),
		userId = tonumber(userId) or 0,
		context = clean(context, 64),
		details = clean(details, 200),
		timestamp = tonumber(timestamp) or 0,
	}
end

-- Uma linha, campos sempre na mesma ordem, fácil de filtrar no console/Log do Creator Hub.
function SecurityLogic.Format(e)
	return ('[Security] event=%s userId=%d context="%s" details="%s" ts=%d'):format(
		e.event,
		e.userId,
		e.context:gsub('"', "'"),
		e.details:gsub('"', "'"),
		e.timestamp
	)
end

-- Contadores por jogador e tipo de evento (sessão). counters[userId][event] = n.
function SecurityLogic.Count(counters, userId, event)
	local c = counters[userId]
	if not c then
		c = {}
		counters[userId] = c
	end
	c[event] = (c[event] or 0) + 1
	return c[event]
end

function SecurityLogic.Snapshot(counters, userId)
	return table.clone(counters[userId] or {})
end

function SecurityLogic.Clear(counters, userId)
	counters[userId] = nil
end

-- Evita inundar o console: emite no máximo 1 linha por (jogador, evento) a cada `window` s.
-- O contador sempre soma; só o warn é limitado.
function SecurityLogic.ShouldEmit(throttle, userId, event, now, window)
	local key = tostring(userId) .. ":" .. event
	local last = throttle[key]
	if last ~= nil and now - last < window then
		return false
	end
	throttle[key] = now
	return true
end

-- Admin = UserId inteiro presente na lista (array de números). Lista vazia = ninguém.
function SecurityLogic.IsAdmin(allowlist, userId)
	if type(userId) ~= "number" or userId ~= userId or userId % 1 ~= 0 or userId <= 0 then
		return false
	end
	for _, id in allowlist or {} do
		if id == userId then
			return true
		end
	end
	return false
end

return SecurityLogic
