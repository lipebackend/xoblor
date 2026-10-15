-- Remotes em ReplicatedStorage.Remotes com rate limit (token bucket), validação e log de abuso.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Guard = require(script.Parent.RemoteGuard)
local SecurityLog = require(script.Parent.SecurityLog)

local RemoteUtil = {}
local folder = ReplicatedStorage:WaitForChild("Remotes")

local MAX_STRIKES = 30 -- chamadas recusadas por janela antes de expulsar
local STRIKE_WINDOW = 60
local strikes = {} -- [player] = { n, since }

Players.PlayerRemoving:Connect(function(p)
	strikes[p] = nil
end)

-- Registra comportamento suspeito (SecurityLog) e expulsa quem insiste (regra antiga, mantida).
-- event: tipo em SecurityLogic.EVENTS (padrão "flag"); context: remote ou sistema.
function RemoteUtil.Flag(player, what, event, context)
	local now = os.clock()
	local s = strikes[player]
	if not s or now - s.since > STRIKE_WINDOW then
		s = { n = 0, since = now }
		strikes[player] = s
	end
	s.n += 1
	SecurityLog.Record(player, event or "flag", context or "", ("%s [strike %d]"):format(tostring(what), s.n))
	if s.n >= MAX_STRIKES and player.Parent then
		player:Kick("Atividade suspeita detectada.")
	end
end

function RemoteUtil.Get(name, className)
	local r = folder:FindFirstChild(name)
	if r and not r:IsA(className) then
		error(("Remote %s existe com classe %s"):format(name, r.ClassName))
	end
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
	end
	return r
end

-- Rate limit e schema de TODOS os RemoteFunctions ficam aqui (um lugar só).
-- interval/burst = token bucket por jogador e por remote. args = validadores (RemoteGuard.V).
local V = Guard.V
RemoteUtil.REMOTES = {
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
	AtmAction = { interval = 0.5, burst = 2, args = { V.OneOf("balance", "deposit", "withdraw"), V.Optional(V.Money) } },
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
-- Teto global por jogador, somando todos os remotes (anti-flood).
RemoteUtil.GLOBAL = { interval = 0.1, burst = 20 }

-- Token bucket por jogador: `burst` chamadas seguidas, recarga de 1 a cada `interval` segundos.
function RemoteUtil.Limiter(interval, burst)
	local buckets = {}
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
	return function(player)
		local ok
		ok, buckets[player] = Guard.Take(buckets[player], os.clock(), interval, burst)
		return ok
	end
end

-- Validadores de payload vindo do cliente (NaN e infinito recusados).
RemoteUtil.IsInt = Guard.IsInt
RemoteUtil.IsId = Guard.IsId

local globalOk = RemoteUtil.Limiter(RemoteUtil.GLOBAL.interval, RemoteUtil.GLOBAL.burst)

-- Liga um RemoteFunction registrado em REMOTES: rate limit (por remote e global), schema, pcall e log.
-- handler(player, ...) -> ok, res. `override` opcional troca interval/burst (ex.: valor de config).
function RemoteUtil.BindFunction(name, handler, override)
	local spec = RemoteUtil.REMOTES[name]
	assert(spec, "Remote sem registro em RemoteUtil.REMOTES: " .. tostring(name))
	local interval = override and override.interval or spec.interval
	local burst = override and override.burst or spec.burst
	local rateOk = RemoteUtil.Limiter(interval, burst)
	RemoteUtil.Get(name, "RemoteFunction").OnServerInvoke = function(player, ...)
		if not globalOk(player) or not rateOk(player) then
			SecurityLog.Record(player, "rate_limit", name, "")
			return false, "RateLimited"
		end
		local valid, bad = Guard.Check(spec.args, select("#", ...), { ... })
		if not valid then
			RemoteUtil.Flag(player, ("argumento %d inválido"):format(bad), "invalid_payload", name)
			return false, "Invalid"
		end
		-- repassa todos os retornos do handler (ex.: BankDeposit devolve ok, banco, movido)
		local r = table.pack(pcall(handler, player, ...))
		if not r[1] then
			warn(("[Remote] %s falhou: %s"):format(name, tostring(r[2])))
			return false, "ServerError"
		end
		if r[2] == false and r[3] == "Invalid" then
			RemoteUtil.Flag(player, "payload inválido", "invalid_payload", name)
		end
		return table.unpack(r, 2, r.n)
	end
end

return RemoteUtil
