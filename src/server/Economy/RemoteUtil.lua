-- Remotes em ReplicatedStorage.Remotes com rate limit (token bucket), validação e log de abuso.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RemoteUtil = {}
local folder = ReplicatedStorage:WaitForChild("Remotes")

local MAX_STRIKES = 30 -- chamadas recusadas por janela antes de expulsar
local STRIKE_WINDOW = 60
local strikes = {} -- [player] = { n, since }

Players.PlayerRemoving:Connect(function(p)
	strikes[p] = nil
end)

-- Registra comportamento suspeito; expulsa quem insiste.
function RemoteUtil.Flag(player, what)
	local now = os.clock()
	local s = strikes[player]
	if not s or now - s.since > STRIKE_WINDOW then
		s = { n = 0, since = now }
		strikes[player] = s
	end
	s.n += 1
	warn(("[Security] %s (%d): %s [%d]"):format(player.Name, player.UserId, what, s.n))
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

-- Token bucket: `burst` chamadas seguidas, recarga de 1 a cada `interval` segundos.
function RemoteUtil.Limiter(interval, burst)
	burst = burst or 1
	local buckets = {}
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
	return function(player)
		local now = os.clock()
		local b = buckets[player]
		if not b then
			b = { tokens = burst, at = now }
			buckets[player] = b
		end
		b.tokens = math.min(burst, b.tokens + (now - b.at) / interval)
		b.at = now
		if b.tokens < 1 then
			return false
		end
		b.tokens -= 1
		return true
	end
end

-- Validadores de payload vindo do cliente.
function RemoteUtil.IsInt(n, min, max)
	return type(n) == "number" and n == n and n % 1 == 0 and n >= (min or -math.huge) and n <= (max or math.huge)
end

function RemoteUtil.IsId(s)
	return type(s) == "string" and #s > 0 and #s <= 64 and s:match("^[%w_]+$") ~= nil
end

-- Liga um RemoteFunction com rate limit, pcall e log. handler(player, ...) -> ok, res
function RemoteUtil.BindFunction(name, interval, burst, handler)
	local rateOk = RemoteUtil.Limiter(interval, burst)
	RemoteUtil.Get(name, "RemoteFunction").OnServerInvoke = function(player, ...)
		if not rateOk(player) then
			return false, "RateLimited"
		end
		local ok, a, b = pcall(handler, player, ...)
		if not ok then
			warn(("[Remote] %s falhou: %s"):format(name, tostring(a)))
			return false, "ServerError"
		end
		if a == false and b == "Invalid" then
			RemoteUtil.Flag(player, name .. ": payload inválido")
		end
		return a, b
	end
end

return RemoteUtil
