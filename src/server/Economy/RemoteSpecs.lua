-- Rate limit e schema de TODOS os RemoteFunctions (cliente -> servidor) num lugar só, puro
-- (testado com lune). interval/burst = token bucket por jogador e por remote; args = validadores.
-- Build recebe RemoteGuard.V para não depender de require entre módulos.
local RemoteSpecs = {}

function RemoteSpecs.Build(V)
	return {
		VehicleAction = { interval = 2, burst = 2, args = { V.OneOf("spawn", "despawn", "list"), V.Optional(V.Id) } },
		RequestPurchase = { interval = 0.5, burst = 2, args = { V.Id } },
		RobAttempt = { interval = 0.5, burst = 1, args = { V.UserId } },
		RideStart = { interval = 1, burst = 1, args = {} },
		RideCancel = { interval = 1, burst = 1, args = {} },
		ClaimDaily = { interval = 1, burst = 2, args = {} },
		Revive = { interval = 0.5, burst = 1, args = { V.UserId } },
		CallMedic = { interval = 30, burst = 1, args = {} }, -- o bind usa Config.CALL_INTERVAL do MedicLogic
		QuitJob = { interval = 1, burst = 1, args = {} },
		StoreBuy = { interval = 0.5, burst = 2, args = { V.Id } },
		AtmAction = {
			interval = 0.5,
			burst = 2,
			args = { V.OneOf("balance", "deposit", "withdraw"), V.Optional(V.Money) },
		},
		InteractClose = { interval = 0.5, burst = 2, args = {} },
		HouseAction = {
			interval = 0.5,
			burst = 3,
			args = { V.OneOf("list", "rent", "buy", "invite", "uninvite"), V.Optional(V.Id), V.Optional(V.UserId) },
		},
		BankDeposit = { interval = 0.5, burst = 2, args = { V.Money } },
		BankWithdraw = { interval = 0.5, burst = 2, args = { V.Money } },
		BankGet = { interval = 0.5, burst = 3, args = {} },
		Pix = { interval = 1, burst = 2, args = { V.UserId, V.Money } },
		Arrest = { interval = 0.5, burst = 1, args = { V.UserId } },
		SecurityQuery = { interval = 1, burst = 2, args = { V.Optional(V.UserId) } }, -- só admins (SecurityLog)
	}
end

-- Teto global por jogador, somando todos os remotes (anti-flood).
RemoteSpecs.GLOBAL = { interval = 0.1, burst = 20 }

return RemoteSpecs
