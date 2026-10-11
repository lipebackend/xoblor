local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyService = {}
local balances = {} -- [player] = number
local MAX_BALANCE = 1e12

local changed = Instance.new("BindableEvent")
EconomyService.BalanceChanged = changed.Event

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BalanceChanged")

local function validAmount(n)
	return type(n) == "number" and n == n and n > 0 and n % 1 == 0 and n <= MAX_BALANCE
end

local function setBalance(player, value, reason)
	balances[player] = value
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Coins") then
		ls.Coins.Value = value
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
	coins.Name = "Coins"
	coins.Parent = ls
	ls.Parent = player
	setBalance(player, math.clamp(tonumber(savedBalance) or 0, 0, MAX_BALANCE), "load")
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

function EconomyService.AddCoins(player, amount, reason)
	if not validAmount(amount) then
		return false, "InvalidAmount"
	end
	local b = balances[player]
	if b == nil then
		return false, "NotLoaded"
	end
	local new = math.min(b + amount, MAX_BALANCE)
	setBalance(player, new, reason or "add")
	return true, new
end

function EconomyService.SpendCoins(player, amount, reason)
	if not validAmount(amount) then
		return false, "InvalidAmount"
	end
	local b = balances[player]
	if b == nil then
		return false, "NotLoaded"
	end
	if b < amount then
		return false, "InsufficientFunds"
	end
	setBalance(player, b - amount, reason or "spend")
	return true, b - amount
end

function EconomyService.Transfer(from, to, amount)
	if from == to then
		return false, "SamePlayer"
	end
	if not validAmount(amount) then
		return false, "InvalidAmount"
	end
	if balances[from] == nil or balances[to] == nil then
		return false, "NotLoaded"
	end
	if balances[from] < amount then
		return false, "InsufficientFunds"
	end
	setBalance(from, balances[from] - amount, "transfer_out")
	setBalance(to, math.min(balances[to] + amount, MAX_BALANCE), "transfer_in")
	warn(("[Economy] Transfer %d de %d para %d"):format(amount, from.UserId, to.UserId))
	return true, balances[from]
end

function EconomyService.GetSnapshot(player)
	return balances[player]
end

return EconomyService
