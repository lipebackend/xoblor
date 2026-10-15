-- Remotes em ReplicatedStorage.Remotes com rate limit (token bucket), validação e log de abuso.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Guard = require(script.Parent.RemoteGuard)
local Specs = require(script.Parent.RemoteSpecs)
local SecurityLog = require(script.Parent.SecurityLog)
local SecurityLogic = require(script.Parent.SecurityLogic)

local RemoteUtil = {}
Guard.SetStudio(RunService:IsStudio()) -- UserIds negativos só no Studio
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
	local s, n, kick = SecurityLogic.Strike(strikes[player], os.clock(), STRIKE_WINDOW, MAX_STRIKES)
	strikes[player] = s
	SecurityLog.Record(player, event or "flag", context or "", ("%s [strike %d]"):format(tostring(what), n))
	if kick and player.Parent then
		-- registra antes de expulsar (depois do Kick o jogador some e o contador é limpo)
		SecurityLog.Record(
			player,
			"kick",
			context or "",
			("%d strikes em %ds; último: %s"):format(n, STRIKE_WINDOW, tostring(what))
		)
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

-- Rate limit e schema de TODOS os RemoteFunctions: RemoteSpecs (puro, testado com lune).
RemoteUtil.REMOTES = Specs.Build(Guard.V)
RemoteUtil.GLOBAL = Specs.GLOBAL

-- Token bucket por jogador: `burst` chamadas seguidas, recarga de 1 a cada `interval` segundos.
function RemoteUtil.Limiter(interval, burst)
	local buckets = {}
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
	return Guard.Limiter(interval, burst, os.clock, buckets)
end

-- Validadores de payload vindo do cliente (NaN e infinito recusados).
RemoteUtil.IsInt = Guard.IsInt
RemoteUtil.IsId = Guard.IsId
function RemoteUtil.IsUserId(v)
	return Guard.IsUserId(v, Guard.Studio)
end

local globalOk = RemoteUtil.Limiter(RemoteUtil.GLOBAL.interval, RemoteUtil.GLOBAL.burst)

-- Liga um RemoteFunction registrado em REMOTES: rate limit (por remote e global), schema, pcall e log.
-- handler(player, ...) -> ok, res. `override` opcional troca interval/burst (ex.: valor de config).
function RemoteUtil.BindFunction(name, handler, override)
	local spec = RemoteUtil.REMOTES[name]
	assert(spec, "Remote sem registro em RemoteUtil.REMOTES: " .. tostring(name))
	local interval = override and override.interval or spec.interval
	local burst = override and override.burst or spec.burst
	RemoteUtil.Get(name, "RemoteFunction").OnServerInvoke = Guard.Invoker(name, spec.args, handler, {
		global = globalOk,
		rate = RemoteUtil.Limiter(interval, burst),
		record = SecurityLog.Record,
		flag = RemoteUtil.Flag,
		log = warn,
	})
end

return RemoteUtil
