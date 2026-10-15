-- Empregos via ProximityPrompt nas partes com tag JobStation (atributo "JobId").
-- Salário a cada PAY_INTERVAL; mototaxi recebe por corrida via JobService.PayRide.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local RemoteUtil = require(script.Parent.RemoteUtil)
local JailState = require(script.Parent.JailState)
local JobCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("JobCatalog"))

local JobService = {}
local VIP_GAMEPASS_ID = require(script.Parent.GamePasses).IDS.VIP -- ID real em GamePasses.lua
local VIP_MULTIPLIER = 1.5
local XP_PER_PAY = 10

local jobChanged = RemoteUtil.Get("JobChanged", "RemoteEvent")
local rateOk = RemoteUtil.Limiter(1)
local vipCache = {}

-- times
for name, color in pairs(JobCatalog.Teams) do
	if not Teams:FindFirstChild(name) then
		local t = Instance.new("Team")
		t.Name = name
		t.TeamColor = color
		t.AutoAssignable = (name == "Civis")
		t.Parent = Teams
	end
end

local function extraOf(player)
	if not Economy.IsLoaded(player) then
		return nil
	end
	local extra = Data.GetExtra(player)
	if extra then
		extra.JobXP = extra.JobXP or {}
	end
	return extra
end

local function isVip(player)
	if VIP_GAMEPASS_ID == 0 then
		return false
	end
	if vipCache[player] == nil then
		local ok, owns =
			pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, VIP_GAMEPASS_ID)
		vipCache[player] = ok and owns or false
	end
	return vipCache[player]
end

local function applyTeam(player, jobId)
	local job = JobCatalog.Get(jobId)
	local team = Teams:FindFirstChild(job and job.Team or "Civis")
	if team then
		player.Team = team
	end
end

function JobService.GetJob(player)
	local extra = extraOf(player)
	return extra and extra.Job or nil
end

function JobService.SetJob(player, jobId)
	local extra = extraOf(player)
	if not extra then
		return false, "NotLoaded"
	end
	if jobId ~= nil and not JobCatalog.Get(jobId) then
		return false, "UnknownJob"
	end
	if jobId ~= nil and not JailState.Allowed(player, "Job") then
		return false, "Jailed"
	end
	extra.Job = jobId
	applyTeam(player, jobId)
	jobChanged:FireClient(player, jobId, jobId and extra.JobXP[jobId] or 0)
	return true, jobId
end

local function pay(player, jobId, reason)
	local extra = extraOf(player)
	if not extra or extra.Job ~= jobId then
		return false, "NotEmployed"
	end
	local xp = extra.JobXP[jobId] or 0
	local amount = JobCatalog.SalaryFor(jobId, xp, isVip(player) and VIP_MULTIPLIER or 1)
	local ok, res = Economy.AddCoins(player, amount, reason)
	if ok then
		extra.JobXP[jobId] = xp + XP_PER_PAY
	end
	return ok, res
end

-- chamado pelo sistema de corridas (servidor) quando uma corrida termina
function JobService.PayRide(player)
	return pay(player, "mototaxi", "job:mototaxi")
end

-- estações de emprego
local function hookStation(part)
	local jobId = part:GetAttribute("JobId")
	local job = JobCatalog.Get(jobId)
	if not job then
		warn("[Jobs] JobStation sem JobId válido: " .. part:GetFullName())
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Trabalhar"
	prompt.ObjectText = job.Name
	prompt.HoldDuration = 0.5
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if not rateOk(player) then
			return
		end
		if JobService.GetJob(player) == jobId then
			JobService.SetJob(player, nil)
		else
			JobService.SetJob(player, jobId)
		end
	end)
end
CollectionService:GetInstanceAddedSignal("JobStation"):Connect(hookStation)
for _, part in CollectionService:GetTagged("JobStation") do
	hookStation(part)
end

-- pedir demissão pelo menu
RemoteUtil.BindFunction("QuitJob", 1, 1, function(player)
	return JobService.SetJob(player, nil)
end)

-- restaura time ao carregar
Economy.BalanceChanged:Connect(function(player, _, reason)
	if reason == "load" then
		local extra = extraOf(player)
		applyTeam(player, extra and extra.Job)
	end
end)

-- salário periódico
task.spawn(function()
	while true do
		task.wait(JobCatalog.PAY_INTERVAL)
		for _, p in Players:GetPlayers() do
			local jobId = JobService.GetJob(p)
			local job = jobId and JobCatalog.Get(jobId)
			if job and not job.PayPerRide then
				task.spawn(pay, p, jobId, "job:" .. jobId)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	vipCache[p] = nil
end)

return JobService
