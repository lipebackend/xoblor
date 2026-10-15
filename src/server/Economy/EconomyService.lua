local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logic = require(script.Parent.EconomyLogic)

local EconomyService = {}
local balances = {}

local changed = Instance.new("BindableEvent")
EconomyService.BalanceChanged = changed.Event

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BalanceChanged")

local function setBalance(player, value, reason)
	balances[player] = value
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Reais") then
		ls.Reais.Value = value
	end
	remote:FireClient(player, value)
	changed:Fire(player, value, reason)
end

function EconomyService.IsLoaded(player)
	return balances[player] ~= nil
end

function EconomyService.Init(player, savedBalance)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Reais"
	coins.Parent = ls
	ls.Parent = player
	setBalance(player, Logic.NormalizeBalance(savedBalance), "load")
end

function EconomyService.Release(player)
	balances[player] = nil
end

function EconomyService.GetBalance(player)
	local b = balances[player]
	if b == nil then
		return false, "NotLoaded"
	end
	return true, b
end

-- Retorna true, novo saldo, valor creditado (pode ser < amount perto do teto) ou false, erro.
-- Carteira já no teto: false, "WalletFull".
function EconomyService.AddCoins(player, amount, reason)
	local ok, new, credited = Logic.Add(balances[player], amount)
	if not ok then
		return false, new
	end
	setBalance(player, new, reason or "add")
	return true, new, credited
end

function EconomyService.SpendCoins(player, amount, reason)
	local ok, new = Logic.Spend(balances[player], amount)
	if not ok then
		return false, new
	end
	setBalance(player, new, reason or "spend")
	return true, new
end

function EconomyService.Transfer(from, to, amount)
	local ok, newFrom, newTo = Logic.Transfer(balances[from], balances[to], amount, from == to)
	if not ok then
		return false, newFrom
	end
	setBalance(from, newFrom, "transfer_out")
	setBalance(to, newTo, "transfer_in")
	warn(("[Economy] Transfer %d de %d para %d"):format(amount, from.UserId, to.UserId))
	return true, balances[from]
end

function EconomyService.GetSnapshot(player)
	return balances[player]
end

return EconomyService
