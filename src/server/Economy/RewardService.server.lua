local Players = game:GetService("Players")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local RemoteUtil = require(script.Parent.RemoteUtil)

local DAILY_AMOUNT, DAILY_CD = 100, 24 * 3600
local PLAYTIME_AMOUNT, PLAYTIME_EVERY = 10, 300
local MAX_EVENT_REWARD = 10000

local function rewards(p)
	local extra = Data.GetExtra(p)
	if not extra then
		return nil
	end
	if type(extra.Rewards) ~= "table" then
		extra.Rewards = {}
	end
	local last = tonumber(extra.Rewards.LastDaily) or 0
	-- relógio no futuro (save adulterado/servidor com hora errada) não trava nem libera infinito
	if last ~= last or last > os.time() then
		last = 0
	end
	extra.Rewards.LastDaily = last
	return extra.Rewards
end

RemoteUtil.BindFunction("ClaimDaily", 1, 2, function(player)
	if not Economy.IsLoaded(player) then
		return false, "NotLoaded"
	end
	local r = rewards(player)
	local t = os.time()
	local remaining = DAILY_CD - (t - r.LastDaily)
	if remaining > 0 then
		return false, remaining
	end
	local ok, res = Economy.AddCoins(player, DAILY_AMOUNT, "daily")
	if ok then
		r.LastDaily = t
	end
	return ok, res
end)

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
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "InvalidTarget"
	end
	if not RemoteUtil.IsInt(amount, 1, MAX_EVENT_REWARD) then
		warn(("[Reward] recompensa de evento recusada: %s"):format(tostring(amount)))
		return false, "InvalidAmount"
	end
	return Economy.AddCoins(player, amount, "event:" .. tostring(reason))
end
