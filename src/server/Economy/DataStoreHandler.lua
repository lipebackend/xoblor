local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Economy = require(script.Parent.EconomyService)

local store = DataStoreService:GetDataStore("EconomyV1")
local AUTOSAVE = 60
local RETRIES = 3
local LOCK_TTL = 300
local RECEIPT_TTL = 30 * 24 * 3600

local Handler = {}
local extraData = {} -- [player] = tabela (Owned, Rewards, Receipts)

local function key(p)
	return "Player_" .. p.UserId
end

local function retry(fn)
	local ok, res
	for i = 1, RETRIES do
		ok, res = pcall(fn)
		if ok then
			return true, res
		end
		warn("[DataStore] tentativa " .. i .. " falhou: " .. tostring(res))
		task.wait(2 ^ i)
	end
	return false, res
end

local function load(player)
	local data
	for attempt = 1, 5 do
		local locked = false
		local ok = retry(function()
			store:UpdateAsync(key(player), function(old)
				old = old or {}
				local now = os.time()
				if old.SessionJobId and old.SessionJobId ~= game.JobId and now - (old.SessionTime or 0) < LOCK_TTL then
					locked = true
					return nil
				end
				locked = false
				old.SessionJobId, old.SessionTime = game.JobId, now
				data = old
				return old
			end)
		end)
		if not ok then
			player:Kick("Falha ao carregar seus dados. Tente novamente.")
			return
		end
		if not locked then
			break
		end
		data = nil
		task.wait(attempt * 3)
	end
	if not data then
		player:Kick("Sua sessão ainda está ativa em outro servidor. Tente de novo.")
		return
	end
	extraData[player] = data.Extra or {}
	if player.Parent then
		Economy.Init(player, data.Coins)
	end
end

local function save(player, release)
	local coins = Economy.GetSnapshot(player)
	if coins == nil then
		return false
	end
	local extra = extraData[player] or {}
	local owned = false
	local ok = retry(function()
		store:UpdateAsync(key(player), function(old)
			old = old or {}
			if old.SessionJobId and old.SessionJobId ~= game.JobId then
				owned = false
				return nil
			end
			owned = true
			local now = os.time()
			if extra.Receipts then
				for id, t in pairs(extra.Receipts) do
					if now - t > RECEIPT_TTL then
						extra.Receipts[id] = nil
					end
				end
			end
			return {
				Coins = coins,
				Extra = extra,
				Version = 1,
				SessionJobId = (not release) and game.JobId or nil,
				SessionTime = (not release) and now or nil,
			}
		end)
	end)
	return ok and owned
end

function Handler.GetExtra(player)
	return extraData[player]
end

function Handler.SaveNow(player)
	return save(player, false)
end

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end

Players.PlayerRemoving:Connect(function(p)
	save(p, true)
	Economy.Release(p)
	extraData[p] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		task.wait(1)
	end
	local pending = 0
	for _, p in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			save(p, true)
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE)
		for _, p in Players:GetPlayers() do
			task.spawn(save, p, false)
		end
	end
end)

return Handler
