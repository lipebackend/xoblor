-- Validação de movimento no servidor (regras puras, testadas com lune em tests/).
-- Mesmo padrão do RideLogic.Sample: compara cada amostra com a anterior e o tempo entre elas.
-- Posições: qualquer valor com X/Y/Z (Vector3 no Roblox, tabela nos testes).
local MoveLogic = {}

MoveLogic.Config = {
	SAMPLE_INTERVAL = 0.5, -- segundos entre amostras
	SPEED_SLACK = 1.5, -- folga sobre a velocidade máxima (lag, física, rampas)
	FLAT_SLACK = 8, -- studs extras por amostra (pulo, empurrão, correção de rede)
	UP_SPEED = 60, -- studs/s para cima (pulo/escada); queda não tem limite
	VEHICLE_SPEED = 120, -- piso para quem está num VehicleSeat (mototaxi/carro)
	BLOCK_SECONDS = 5, -- ações físicas bloqueadas após um salto impossível
	TELEPORT_GRACE = 2, -- segundos após teleporte do servidor/respawn em que saltos são ignorados
}

function MoveLogic.New()
	return { LastPos = nil, LastAt = 0, BlockedUntil = 0, GraceUntil = 0, Jumps = 0 }
end

-- Velocidade horizontal máxima aceitável. walkSpeed vem do Humanoid no servidor
-- (alteração do cliente não replica); seatMaxSpeed só quando sentado num VehicleSeat.
function MoveLogic.MaxSpeed(walkSpeed, seatMaxSpeed, cfg)
	cfg = cfg or MoveLogic.Config
	local w = (type(walkSpeed) == "number" and walkSpeed == walkSpeed and walkSpeed > 0) and walkSpeed or 16
	if seatMaxSpeed ~= nil then
		local s = (type(seatMaxSpeed) == "number" and seatMaxSpeed == seatMaxSpeed) and seatMaxSpeed or 0
		return math.max(w, s, cfg.VEHICLE_SPEED)
	end
	return w
end

-- Teleporte legítimo (cadeia, soltura, hospital, casa, respawn): reancora e abre uma janela curta.
function MoveLogic.AllowTeleport(s, now, cfg)
	cfg = cfg or MoveLogic.Config
	s.LastPos = nil
	s.GraceUntil = now + cfg.TELEPORT_GRACE
end

local function finite(n)
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Processa uma amostra. Retorna "anchor" (sem referência ainda), "ok", "grace" (salto
-- ignorado por teleporte permitido) ou "jump" (salto impossível: bloqueia ações físicas).
function MoveLogic.Sample(s, pos, now, maxSpeed, cfg)
	cfg = cfg or MoveLogic.Config
	if pos == nil then
		s.LastPos = nil -- sem personagem: a próxima amostra só ancora
		return "anchor"
	end
	if not (finite(pos.X) and finite(pos.Y) and finite(pos.Z)) then
		s.LastPos = nil
		s.BlockedUntil = now + cfg.BLOCK_SECONDS
		s.Jumps += 1
		return "jump" -- posição NaN/inf é sempre suspeita
	end
	local last = s.LastPos
	local dt = math.max(0, now - s.LastAt)
	s.LastPos, s.LastAt = pos, now
	if last == nil then
		return "anchor"
	end
	local dx, dz = pos.X - last.X, pos.Z - last.Z
	local horizontal = math.sqrt(dx * dx + dz * dz)
	local up = math.max(0, pos.Y - last.Y)
	local okH = horizontal <= maxSpeed * cfg.SPEED_SLACK * dt + cfg.FLAT_SLACK
	local okV = up <= cfg.UP_SPEED * dt + cfg.FLAT_SLACK
	if okH and okV then
		return "ok"
	end
	if now < s.GraceUntil then
		return "grace"
	end
	s.BlockedUntil = now + cfg.BLOCK_SECONDS
	s.Jumps += 1
	return "jump"
end

function MoveLogic.IsBlocked(s, now)
	return s ~= nil and now < s.BlockedUntil
end

return MoveLogic
