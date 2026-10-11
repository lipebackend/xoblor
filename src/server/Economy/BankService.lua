-- Carteira = saldo do EconomyService (leaderstats Reais). Banco = Extra.Bank.
-- Pix usa EconomyService.Transfer (carteira -> carteira), limite R$5.000 por hora.
local Players = game:GetService("Players")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local RemoteUtil = require(script.Parent.RemoteUtil)

local BankService = {}
local PIX_LIMIT = 5000
local PIX_WINDOW = 3600
local MAX_BANK = 1e12

local bankChanged = RemoteUtil.Get("BankChanged", "RemoteEvent")
local rateOk = RemoteUtil.Limiter(0.5)

local function validAmount(n)
	return type(n) == "number" and n == n and n > 0 and n % 1 == 0 and n <= MAX_BANK
end

local function extraOf(player)
	if not Economy.IsLoaded(player) then
		return nil
	end
	local extra = Data.GetExtra(player)
	if not extra then
		return nil
	end
	extra.Bank = tonumber(extra.Bank) or 0
	extra.PixLog = extra.PixLog or {}
	return extra
end

local function notify(player, extra)
	bankChanged:FireClient(player, extra.Bank)
end

function BankService.GetBank(player)
	local extra = extraOf(player)
	if not extra then
		return false, "NotLoaded"
	end
	return true, extra.Bank
end

function BankService.Deposit(player, amount)
	if not validAmount(amount) then
		return false, "InvalidAmount"
	end
	local extra = extraOf(player)
	if not extra then
		return false, "NotLoaded"
	end
	local ok, err = Economy.SpendCoins(player, amount, "bank:deposit")
	if not ok then
		return false, err
	end
	extra.Bank = math.min(extra.Bank + amount, MAX_BANK)
	notify(player, extra)
	return true, extra.Bank
end

function BankService.Withdraw(player, amount)
	if not validAmount(amount) then
		return false, "InvalidAmount"
	end
	local extra = extraOf(player)
	if not extra then
		return false, "NotLoaded"
	end
	if extra.Bank < amount then
		return false, "InsufficientFunds"
	end
	extra.Bank -= amount
	local ok, err = Economy.AddCoins(player, amount, "bank:withdraw")
	if not ok then
		extra.Bank += amount
		return false, err
	end
	notify(player, extra)
	return true, extra.Bank
end

local function pixUsed(extra, now)
	local used, kept = 0, {}
	for _, e in ipairs(extra.PixLog) do
		if now - e.t < PIX_WINDOW then
			used += e.v
			table.insert(kept, e)
		end
	end
	extra.PixLog = kept
	return used
end

function BankService.Pix(from, to, amount)
	if typeof(to) ~= "Instance" or not to:IsA("Player") or to.Parent ~= Players then
		return false, "InvalidTarget"
	end
	if not validAmount(amount) then
		return false, "InvalidAmount"
	end
	local extra = extraOf(from)
	if not extra or not Economy.IsLoaded(to) then
		return false, "NotLoaded"
	end
	local now = os.time()
	if pixUsed(extra, now) + amount > PIX_LIMIT then
		return false, "PixLimit"
	end
	local ok, err = Economy.Transfer(from, to, amount)
	if not ok then
		return false, err
	end
	table.insert(extra.PixLog, { t = now, v = amount })
	return true, err
end

-- Remotes (caixa eletrônico e celular)
RemoteUtil.Get("BankDeposit", "RemoteFunction").OnServerInvoke = function(player, amount)
	if not rateOk(player) then
		return false, "RateLimited"
	end
	return BankService.Deposit(player, amount)
end

RemoteUtil.Get("BankWithdraw", "RemoteFunction").OnServerInvoke = function(player, amount)
	if not rateOk(player) then
		return false, "RateLimited"
	end
	return BankService.Withdraw(player, amount)
end

RemoteUtil.Get("BankGet", "RemoteFunction").OnServerInvoke = function(player)
	if not rateOk(player) then
		return false, "RateLimited"
	end
	return BankService.GetBank(player)
end

RemoteUtil.Get("Pix", "RemoteFunction").OnServerInvoke = function(player, targetUserId, amount)
	if not rateOk(player) then
		return false, "RateLimited"
	end
	if type(targetUserId) ~= "number" then
		warn(("[Bank] payload suspeito de %d"):format(player.UserId))
		return false, "InvalidTarget"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return false, "InvalidTarget"
	end
	local ok, res = BankService.Pix(player, target, amount)
	if not ok and res == "PixLimit" then
		warn(("[Bank] Pix acima do limite: %d"):format(player.UserId))
	end
	return ok, res
end

return BankService
