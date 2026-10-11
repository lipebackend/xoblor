local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Economy = require(script.Parent.EconomyService)

local store = DataStoreService:GetDataStore("EconomyV1")
local AUTOSAVE = 60
local RETRIES = 3
local LOCK_TIMEOUT = 300 -- trava de sessão expira em 5 min
local LOCK_WAIT_TRIES = 5
local RECEIPT_TTL = 30 * 24 * 3600

local CLOSE_TIMEOUT = 25 -- BindToClose tem 30s no total

local Handler = {}
local extraData = {}
local saving = {} -- [player] = true enquanto um save está em andamento

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

local function pruneReceipts(extra)
	if not extra.Receipts then
		return
	end
	local now = os.time()
	for id, t in pairs(extra.Receipts) do
		if now - t > RECEIPT_TTL then
			extra.Receipts[id] = nil
		end
	end
end

-- grava só se esta sessão for a dona; release=true libera a trava
local function doSave(player, release)
	local coins = Economy.GetSnapshot(player)
	if coins == nil then
		return false
	end
	local extra = extraData[player] or {}
	pruneReceipts(extra)
	local owned = false
	local ok = retry(function()
		store:UpdateAsync(key(player), function(old)
			old = old or {}
			if old.SessionJobId and old.SessionJobId ~= game.JobId then
				owned = false
				return nil -- outro servidor é o dono: não sobrescreve
			end
			owned = true
			return {
				Coins = coins,
				Extra = extra,
				Version = 1,
				SessionJobId = (not release) and game.JobId or nil,
				SessionTime = os.time(),
			}
		end)
	end)
	if not ok then
		warn(("[DataStore] save de %d falhou após %d tentativas"):format(player.UserId, RETRIES))
	end
	return ok and owned
end

-- serializa saves do mesmo jogador (autosave x SaveNow x saída não se atropelam)
local function save(player, release)
	while saving[player] do
		task.wait()
	end
	saving[player] = true
	local ok, res = pcall(doSave, player, release)
	saving[player] = nil
	if not ok then
		warn("[DataStore] erro no save: " .. tostring(res))
		return false
	end
	return res
end

local function load(player)
	local data
	for _ = 1, LOCK_WAIT_TRIES do
		local locked = false
		local ok = retry(function()
			store:UpdateAsync(key(player), function(old)
				old = old or {}
				if
					old.SessionJobId
					and old.SessionJobId ~= game.JobId
					and os.time() - (old.SessionTime or 0) < LOCK_TIMEOUT
				then
					locked = true
					return nil
				end
				locked = false
				old.SessionJobId = game.JobId
				old.SessionTime = os.time()
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
		task.wait(5)
	end
	if not data then
		player:Kick("Seus dados ainda estão em uso em outro servidor. Tente de novo em instantes.")
		return
	end
	extraData[player] = type(data.Extra) == "table" and data.Extra or {}
	if player.Parent then
		Economy.Init(player, data.Coins)
	end
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

local released = {} -- jogadores já salvos na saída (evita save duplo com o BindToClose)

local function saveAndRelease(p)
	if released[p] then
		return
	end
	released[p] = true
	save(p, true)
	Economy.Release(p)
	extraData[p] = nil
	released[p] = nil
end

Players.PlayerRemoving:Connect(saveAndRelease)

game:BindToClose(function()
	if RunService:IsStudio() then
		task.wait(1)
	end
	local pending = 0
	for _, p in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			saveAndRelease(p)
			pending -= 1
		end)
	end
	local deadline = os.clock() + CLOSE_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait()
	end
	if pending > 0 then
		warn(("[DataStore] BindToClose terminou com %d saves pendentes"):format(pending))
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE)
		for _, p in Players:GetPlayers() do
			if not saving[p] then
				task.spawn(save, p, false)
			end
		end
	end
end)

return Handler
