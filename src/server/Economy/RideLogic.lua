-- Regras puras das corridas de mototaxi (sem APIs do Roblox), testadas com lune em tests/.
local RideLogic = {}
RideLogic.ARRIVE_RADIUS = 12 -- studs do ponto de entrega para contar como chegada
RideLogic.MIN_TRIP_DISTANCE = 100 -- destino precisa estar pelo menos a isto da origem
RideLogic.MAX_SPEED = 60 -- studs/s; chegar mais rápido que isso é teleporte
RideLogic.MIN_RIDE_TIME = 10 -- segundos mínimos por corrida
RideLogic.RIDE_TIMEOUT = 300 -- corrida expira sem pagar
RideLogic.COOLDOWN = 15 -- espera entre o fim de uma corrida e a próxima
-- Percurso amostrado pelo servidor (soma dos deslocamentos entre amostras).
RideLogic.SPEED_SLACK = 1.25 -- folga sobre MAX_SPEED por amostra (lag/física)
RideLogic.TELEPORT_FACTOR = 3 -- salto acima de 3x o máximo da amostra é teleporte: não conta nada
RideLogic.MIN_PATH_FRACTION = 0.8 -- percurso precisa ser >= 80% da linha reta origem->destino

-- Tempo mínimo aceitável para percorrer `distance`.
function RideLogic.MinTime(distance)
	if type(distance) ~= "number" or distance ~= distance or distance < 0 then
		distance = 0
	end
	return math.max(RideLogic.MIN_RIDE_TIME, distance / RideLogic.MAX_SPEED)
end

-- Pode começar? Retorna nil se sim, senão o código do erro.
function RideLogic.CanStart(hasJob, activeRide, cooldownUntil, now)
	if not hasJob then
		return "NotMototaxi"
	end
	if activeRide then
		return "RideActive"
	end
	if (tonumber(cooldownUntil) or 0) > now then
		return "Cooldown"
	end
	return nil
end

-- Escolhe um destino. `distances[i]` é a distância da origem ao ponto i.
-- `rand(n)` devolve 1..n (math.random no serviço). Retorna o índice ou nil.
function RideLogic.PickDropoff(distances, rand)
	local ok = {}
	for i, d in ipairs(distances) do
		if type(d) == "number" and d >= RideLogic.MIN_TRIP_DISTANCE then
			table.insert(ok, i)
		end
	end
	if #ok == 0 then
		return nil
	end
	return ok[rand(#ok)]
end

local function dist(a, b)
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Amostra de posição (X/Y/Z: Vector3 no Roblox, tabela nos testes). Soma em ride.Path:
--   até MAX_SPEED*SLACK*dt: conta inteiro; acima (speed hack): conta só o teto;
--   acima de TELEPORT_FACTOR x o teto: teleporte/respawn, conta 0 (ride.Jumps += 1).
-- Sem posição (sem personagem): a próxima amostra só reancora.
function RideLogic.Sample(ride, pos, now)
	ride.Path = ride.Path or 0
	ride.Jumps = ride.Jumps or 0
	if pos == nil then
		ride.LastPos = nil
		return
	end
	if ride.LastPos == nil then
		ride.LastPos, ride.LastAt = pos, now
		return
	end
	local dt = math.max(0, now - ride.LastAt)
	local d = dist(pos, ride.LastPos)
	local cap = RideLogic.MAX_SPEED * RideLogic.SPEED_SLACK * dt
	if d <= cap then
		ride.Path += d
	elseif d <= cap * RideLogic.TELEPORT_FACTOR then
		ride.Path += cap
	else
		ride.Jumps += 1
	end
	ride.LastPos, ride.LastAt = pos, now
end

-- Cria a corrida. startedAt e now usam o mesmo relógio (os.clock no serviço).
function RideLogic.NewRide(dropoffIndex, distance, now)
	return {
		Dropoff = dropoffIndex,
		Distance = distance,
		StartedAt = now,
		MinTime = RideLogic.MinTime(distance),
		ExpiresAt = now + RideLogic.RIDE_TIMEOUT,
	}
end

-- Situação da corrida dada a distância atual até o destino:
-- "Expired", "NotArrived", "TooFast" (chegou antes do tempo mínimo), "ShortPath" (percurso amostrado
-- menor que MIN_PATH_FRACTION da linha reta: teleporte e espera) ou "Arrived". TooFast/ShortPath anulam sem pagar.
function RideLogic.Check(ride, distToDropoff, now)
	if now >= ride.ExpiresAt then
		return "Expired"
	end
	if type(distToDropoff) ~= "number" or distToDropoff ~= distToDropoff or distToDropoff > RideLogic.ARRIVE_RADIUS then
		return "NotArrived"
	end
	if now - ride.StartedAt < ride.MinTime then
		return "TooFast"
	end
	if (ride.Path or 0) < RideLogic.MIN_PATH_FRACTION * (ride.Distance or 0) then
		return "ShortPath"
	end
	return "Arrived"
end

return RideLogic
