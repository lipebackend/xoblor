local R = require("../src/server/Economy/RideLogic")

return function(T)
	local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

	describe("RideLogic.MinTime", function()
		it("piso de MIN_RIDE_TIME", function()
			eq(R.MinTime(0), R.MIN_RIDE_TIME)
			eq(R.MinTime(60), R.MIN_RIDE_TIME)
		end)
		it("cresce com a distância", function()
			eq(R.MinTime(R.MAX_SPEED * 30), 30)
		end)
		it("entrada inválida não quebra", function()
			eq(R.MinTime(nil), R.MIN_RIDE_TIME)
			eq(R.MinTime(0 / 0), R.MIN_RIDE_TIME)
			eq(R.MinTime(-5), R.MIN_RIDE_TIME)
		end)
	end)

	describe("RideLogic.CanStart", function()
		it("livre", function()
			eq(R.CanStart(true, nil, 0, 100), nil)
		end)
		it("sem emprego", function()
			eq(R.CanStart(false, nil, 0, 100), "NotMototaxi")
		end)
		it("uma corrida por vez", function()
			eq(R.CanStart(true, {}, 0, 100), "RideActive")
		end)
		it("cooldown", function()
			eq(R.CanStart(true, nil, 101, 100), "Cooldown")
			eq(R.CanStart(true, nil, 100, 100), nil)
			eq(R.CanStart(true, nil, "x", 100), nil)
		end)
	end)

	describe("RideLogic.PickDropoff", function()
		local first = function()
			return 1
		end
		it("ignora destinos perto demais", function()
			eq(R.PickDropoff({ 10, 50, 400 }, first), 3)
		end)
		it("nenhum destino válido", function()
			eq(R.PickDropoff({}, first), nil)
			eq(R.PickDropoff({ 5, 99 }, first), nil)
		end)
		it("sorteia entre os válidos", function()
			local seen = {}
			for n = 1, 2 do
				seen[R.PickDropoff({ 200, 1, 300 }, function()
					return n
				end)] = true
			end
			truthy(seen[1] and seen[3] and not seen[2])
		end)
	end)

	describe("RideLogic.Check", function()
		local ride = R.NewRide(1, R.MAX_SPEED * 20, 1000) -- tempo mínimo 20s
		it("NewRide calcula tempo mínimo e expiração", function()
			eq(ride.MinTime, 20)
			eq(ride.ExpiresAt, 1000 + R.RIDE_TIMEOUT)
		end)
		it("longe do destino", function()
			eq(R.Check(ride, R.ARRIVE_RADIUS + 1, 1030), "NotArrived")
			eq(R.Check(ride, nil, 1030), "NotArrived")
		end)
		it("chegou rápido demais (teleporte) não paga", function()
			eq(R.Check(ride, 0, 1005), "TooFast")
		end)
		it("chegada válida (com percurso)", function()
			ride.Path = ride.Distance
			eq(R.Check(ride, R.ARRIVE_RADIUS, 1020), "Arrived")
			ride.Path = nil
		end)
		it("expira", function()
			eq(R.Check(ride, 0, 1000 + R.RIDE_TIMEOUT), "Expired")
		end)
	end)

	local function v(x, y, z)
		return { X = x, Y = y or 0, Z = z or 0 }
	end
	-- dirige em linha reta de 0 até `to` a `speed` studs/s, amostrando a cada 0,5s
	local function drive(ride, from, to, speed, t0)
		local t, x = t0, from
		R.Sample(ride, v(x), t)
		while x < to do
			t += 0.5
			x = math.min(to, x + speed * 0.5)
			R.Sample(ride, v(x), t)
		end
		return t
	end

	describe("RideLogic.Sample / ShortPath", function()
		it("corrida normal paga", function()
			local ride = R.NewRide(1, 600, 0)
			local t = drive(ride, 0, 600, 40, 0)
			truthy(math.abs(ride.Path - 600) < 1e-6)
			eq(R.Check(ride, 0, t), "Arrived")
		end)
		it("teleporte e espera: não paga", function()
			local ride = R.NewRide(1, 600, 0)
			R.Sample(ride, v(0), 0)
			R.Sample(ride, v(600), 0.5)
			for t = 1, 30 do
				R.Sample(ride, v(600), t)
			end
			eq(ride.Jumps, 1)
			eq(ride.Path, 0)
			eq(R.Check(ride, 0, 30), "ShortPath")
		end)
		it("desvio lento paga", function()
			local ride = R.NewRide(1, 300, 0)
			R.Sample(ride, v(0), 0)
			local t = 0
			-- vai 200 para o lado e volta, depois segue: percurso > linha reta
			for z = 5, 200, 5 do
				t += 0.5
				R.Sample(ride, v(0, 0, z), t)
			end
			for x = 5, 300, 5 do
				t += 0.5
				R.Sample(ride, v(x, 0, 200 - math.min(200, x)), t)
			end
			truthy(ride.Path > 300)
			eq(R.Check(ride, 0, t), "Arrived")
		end)
		it("speed hack: deslocamento acima do teto conta só o teto", function()
			local ride = R.NewRide(1, 600, 0)
			R.Sample(ride, v(0), 0)
			R.Sample(ride, v(100), 1) -- 100 studs/s; teto = 60*1,25 = 75
			eq(ride.Path, 75)
			eq(ride.Jumps, 0)
		end)
		it("speed hack o caminho todo não completa o percurso a tempo", function()
			local ride = R.NewRide(1, 600, 0)
			local t = drive(ride, 0, 600, 150, 0) -- 150 studs/s: cada amostra conta só 37,5
			truthy(ride.Path < 0.8 * 600)
			eq(R.Check(ride, 0, math.max(t, ride.MinTime)), "ShortPath")
		end)
		it("salto grande é teleporte (respawn) e não conta", function()
			local ride = R.NewRide(1, 600, 0)
			R.Sample(ride, v(0), 0)
			R.Sample(ride, v(1000), 0.5)
			eq(ride.Path, 0)
			eq(ride.Jumps, 1)
		end)
		it("sem personagem: próxima amostra só reancora", function()
			local ride = R.NewRide(1, 600, 0)
			R.Sample(ride, v(0), 0)
			R.Sample(ride, nil, 1)
			R.Sample(ride, v(500), 2)
			eq(ride.Path, 0)
			eq(ride.Jumps, 0)
		end)
		it("limite: exatamente 80% da linha reta paga", function()
			local ride = R.NewRide(1, 100, 0)
			ride.Path = 80
			eq(R.Check(ride, 0, 20), "Arrived")
			ride.Path = 79.9
			eq(R.Check(ride, 0, 20), "ShortPath")
		end)
	end)
end
