-- Regras puras das corridas de mototaxi (sem APIs do Roblox), testadas com lune em tests/.
local RideLogic = {}
RideLogic.ARRIVE_RADIUS = 12 -- studs do ponto de entrega para contar como chegada
RideLogic.MIN_TRIP_DISTANCE = 100 -- destino precisa estar pelo menos a isto da origem
RideLogic.MAX_SPEED = 60 -- studs/s; chegar mais rápido que isso é teleporte
RideLogic.MIN_RIDE_TIME = 10 -- segundos mínimos por corrida
RideLogic.RIDE_TIMEOUT = 300 -- corrida expira sem pagar
RideLogic.COOLDOWN = 15 -- espera entre o fim de uma corrida e a próxima

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
-- "Expired", "NotArrived", "TooFast" (chegou antes do tempo mínimo: o serviço anula sem pagar) ou "Arrived".
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
	return "Arrived"
end

return RideLogic
