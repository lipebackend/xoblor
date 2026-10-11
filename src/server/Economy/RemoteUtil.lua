-- Cria Remotes em ReplicatedStorage.Remotes e aplica limite de chamadas por jogador.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RemoteUtil = {}
local folder = ReplicatedStorage:WaitForChild("Remotes")

function RemoteUtil.Get(name, className)
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
	end
	return r
end

function RemoteUtil.Limiter(interval)
	local last = {}
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
	return function(player)
		local now = os.clock()
		if last[player] and now - last[player] < interval then
			return false
		end
		last[player] = now
		return true
	end
end

return RemoteUtil
