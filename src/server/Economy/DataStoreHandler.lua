local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Economy = require(script.Parent.EconomyService)
local Logic = require(script.Parent.ProfileLogic)
local SecurityLog = require(script.Parent.SecurityLog)
local Schedule = require(script.Parent.AutosaveSchedule)
local Retry = require(script.Parent.DataStoreRetry)

local store = DataStoreService:GetDataStore("EconomyV1")
local AUTOSAVE = 60 -- cada jogador salva a cada 60s, numa fase própria (AutosaveSchedule)
local AUTOSAVE_TICK = 1 -- resolução do agendador
local schedule = Schedule.New(AUTOSAVE)
local RETRIES = 5
local BACKOFF_BASE, BACKOFF_CAP = 1, 8 -- segundos (com jitter)
local LOCK_WAIT_TRIES = 5 -- 5 x 5s esperando uma trava viva antes de desistir
local UPDATE = Enum.DataStoreRequestType.UpdateAsync
local RECEIPT_TTL = 30 * 24 * 3600

local CLOSE_TIMEOUT = 25 -- BindToClose tem 30s no total

local Handler = {}
local extraData = {}
local jailData = {} -- [player] = campo Jail de nível superior ({ Remaining, Reason })
local saving = {} -- [player] = true enquanto um save está em andamento
local closing = false

local function key(p)
	return "Player_" .. p.UserId
end

-- Repetição com backoff exponencial + jitter, sem passar do prazo (BindToClose usa um prazo curto).
-- Antes de cada tentativa espera orçamento de UpdateAsync (até o prazo ou 30s). Regras em DataStoreRetry.
local retryEnv = {
	attempts = RETRIES,
	base = BACKOFF_BASE,
	cap = BACKOFF_CAP,
	clock = os.clock,
	wait = task.wait,
	budget = function()
		return DataStoreService:GetRequestBudgetForRequestType(UPDATE)
	end,
	backoff = Logic.Backoff,
	rand = math.random,
	log = warn,
}
local function retry(fn, deadline)
	return Retry.Run(fn, retryEnv, deadline)
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
local function doSave(player, release, deadline)
	local coins = Economy.GetSnapshot(player)
	if coins == nil then
		return false
	end
	local extra = extraData[player] or {}
	pruneReceipts(extra)
	local owned = false
	local ok = retry(function()
		store:UpdateAsync(key(player), function(old)
			local new = Logic.BuildSave(old, game.JobId, os.time(), coins, extra, jailData[player], release)
			owned = new ~= nil
			return new -- nil: outro servidor é o dono, não sobrescreve
		end)
	end, deadline)
	if not ok then
		warn(("[DataStore] save de %d falhou após %d tentativas"):format(player.UserId, RETRIES))
	elseif not owned and not release and player.Parent then
		-- perdemos a trava (outro servidor tomou): continuar jogando aqui duplicaria progresso
		SecurityLog.Record(player, "session_lock_lost", "DataStore", "trava tomada por outro servidor; expulsando")
		Economy.Release(player)
		extraData[player] = nil
		jailData[player] = nil
		player:Kick("Seus dados foram abertos em outro servidor. Entre de novo.")
	end
	return ok and owned
end

-- serializa saves do mesmo jogador (autosave x SaveNow x saída não se atropelam)
local function save(player, release, deadline)
	while saving[player] do
		task.wait()
	end
	saving[player] = true
	local ok, res = pcall(doSave, player, release, deadline)
	saving[player] = nil
	if not ok then
		warn("[DataStore] erro no save: " .. tostring(res))
		return false
	end
	return res
end

-- libera a trava desta sessão sem mexer nos dados (jogador saiu antes do load terminar)
local function releaseLock(player)
	retry(function()
		store:UpdateAsync(key(player), function(old)
			if not old or old.SessionJobId ~= game.JobId then
				return nil
			end
			old.SessionJobId = nil
			old.SessionTime = nil
			return old
		end)
	end)
end

local function load(player)
	local data
	for _ = 1, LOCK_WAIT_TRIES do
		if not player.Parent then
			return -- saiu enquanto esperava a trava: nada foi travado por este servidor
		end
		local locked, tooNew = false, false
		local ok = retry(function()
			store:UpdateAsync(key(player), function(old)
				local decision = Logic.LockDecision(old, game.JobId, os.time())
				if decision == "locked" then
					locked = true
					return nil
				end
				locked = false
				if decision == "stale" then
					warn(
						("[DataStore] trava morta de %d tomada de %s"):format(player.UserId, tostring(old.SessionJobId))
					)
				end
				local migrated = Logic.Migrate(old, os.time())
				if not migrated then
					tooNew = true
					return nil
				end
				tooNew = false
				migrated.SessionJobId = game.JobId
				migrated.SessionTime = os.time()
				data = migrated
				return migrated
			end)
		end)
		if not ok then
			player:Kick("Falha ao carregar seus dados. Tente novamente.")
			return
		end
		if tooNew then
			player:Kick("Seus dados são de uma versão mais nova do jogo. Entre em outro servidor.")
			return
		end
		if not locked then
			break
		end
		data = nil
		task.wait(5)
	end
	if data and not player.Parent then
		-- saiu durante o UpdateAsync: o PlayerRemoving já rodou sem dados, então solta a trava aqui
		releaseLock(player)
		return
	end
	if not data then
		if not player.Parent then
			return
		end
		player:Kick("Seus dados ainda estão em uso em outro servidor. Tente de novo em instantes.")
		return
	end
	extraData[player] = data.Extra
	jailData[player] = data.Jail
	Economy.Init(player, data.Coins)
	if player.Parent then
		Schedule.Add(schedule, player, os.clock())
	end
end

function Handler.GetExtra(player)
	return extraData[player]
end

-- Campo Jail de nível superior: { Remaining = segundos restantes (0 = solto), Reason = "assalto" etc. }.
-- Já vem normalizado do load; é normalizado de novo a cada save. API igual à do #23.
function Handler.GetJail(player)
	return jailData[player]
end

function Handler.SetJail(player, jail)
	jailData[player] = jail
end

function Handler.SaveNow(player)
	return save(player, false)
end

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end

local released = {} -- jogadores já salvos na saída (evita save duplo com o BindToClose)

local function saveAndRelease(p, deadline)
	if released[p] then
		return
	end
	released[p] = true
	Schedule.Remove(schedule, p)
	save(p, true, deadline)
	Economy.Release(p)
	extraData[p] = nil
	jailData[p] = nil
	released[p] = nil
end

Players.PlayerRemoving:Connect(function(p)
	saveAndRelease(p)
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		task.wait(1)
	end
	closing = true
	local deadline = os.clock() + CLOSE_TIMEOUT
	local pending = 0
	for _, p in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			saveAndRelease(p, deadline)
			pending -= 1
		end)
	end
	while (pending > 0 or next(saving) ~= nil) and os.clock() < deadline do
		task.wait()
	end
	if pending > 0 or next(saving) ~= nil then
		warn(("[DataStore] BindToClose terminou com %d saves pendentes"):format(pending))
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_TICK)
		for _, p in Schedule.Due(schedule, os.clock()) do
			if not p.Parent then
				Schedule.Remove(schedule, p) -- saiu sem passar pelo saveAndRelease
				continue
			end
			-- saving[p]: já tem save em andamento (SaveNow/saída), pula este ciclo
			if not closing and not saving[p] and not released[p] then
				task.spawn(save, p, false)
			end
		end
	end
end)

return Handler
