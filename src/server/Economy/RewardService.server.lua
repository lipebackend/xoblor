local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)

local DAILY_AMOUNT, DAILY_CD = 100, 24 * 3600
local PLAYTIME_AMOUNT, PLAYTIME_EVERY = 10, 300
local lastCall = {}

local function rewards(p)
	local extra = Data.GetExtra(p)
	if not extra then
		return nil
	end
	extra.Rewards = extra.Rewards or { LastDaily = 0 }
	return extra.Rewards
end

RS.Remotes.ClaimDaily.OnServerInvoke = function(player)
	local now = os.clock()
	if lastCall[player] and now - lastCall[player] < 0.5 then
		return false, "RateLimited"
	end
	lastCall[player] = now
	if not Economy.IsLoaded(player) then
		return false, "NotLoaded"
	end
	local r = rewards(player)
	local t = os.time()
	local remaining = DAILY_CD - (t - r.LastDaily)
	if remaining > 0 then
		return false, remaining
	end
	r.LastDaily = t
	return Economy.AddCoins(player, DAILY_AMOUNT, "daily")
end

task.spawn(function()
	while true do
		task.wait(PLAYTIME_EVERY)
		for _, p in Players:GetPlayers() do
			if Economy.IsLoaded(p) then
				Economy.AddCoins(p, PLAYTIME_AMOUNT, "playtime")
			end
		end
	end
end)

local api = Instance.new("BindableFunction")
api.Name = "GiveEventReward"
api.Parent = script
api.OnInvoke = function(player, amount, reason)
	return Economy.AddCoins(player, amount, "event:" .. tostring(reason))
end

Players.PlayerRemoving:Connect(function(p)
	lastCall[p] = nil
end)
