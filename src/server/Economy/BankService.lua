-- Carteira = saldo do EconomyService (leaderstats Reais). Banco = Extra.Bank.
-- Pix usa EconomyService.Transfer (carteira -> carteira), limite R$5.000 por hora.
local Players = game:GetService("Players")
local Economy = require(script.Parent.EconomyService)
local Data = require(script.Parent.DataStoreHandler)
local RemoteUtil = require(script.Parent.RemoteUtil)
local Logic = require(script.Parent.EconomyLogic)

local BankService = {}
local PIX_LIMIT = 5000
local PIX_WINDOW = 3600
local MAX_BANK = 1e12

local bankChanged = RemoteUtil.Get("BankChanged", "RemoteEvent")

local function validAmount(n)
	return RemoteUtil.IsInt(n, 1, MAX_BANK)
end

local function extraOf(player)
	if not Economy.IsLoaded(player) then
		return nil
	end
	local extra = Data.GetExtra(player)
	if not extra then
		return nil
	end
	local bank = tonumber(extra.Bank) or 0
	extra.Bank = (bank == bank and bank >= 0) and math.floor(bank) or 0
	if type(extra.PixLog) ~= "table" then
		extra.PixLog = {}
	end
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
	-- Só debita do banco o que coube na carteira (perto do teto o saque é parcial).
	local ok, err, credited = Economy.AddCoins(player, amount, "bank:withdraw")
	if not ok then
		return false, err
	end
	extra.Bank -= credited
	notify(player, extra)
	return true, extra.Bank, credited
end

-- Crédito direto no banco (usado pelo excedente de compras com Robux). Retorna o valor creditado.
function BankService.CreditBank(player, amount)
	local extra = extraOf(player)
	if not extra or not RemoteUtil.IsInt(amount, 0, MAX_BANK) then
		return 0
	end
	local credited = math.min(amount, MAX_BANK - extra.Bank)
	if credited > 0 then
		extra.Bank += credited
		notify(player, extra)
	end
	return credited
end

local function pixUsed(extra, now)
	local used, kept = Logic.PixUsed(extra.PixLog, now, PIX_WINDOW)
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
	local entry = { t = now, v = amount }
	table.insert(extra.PixLog, entry) -- reserva o limite antes de transferir
	local ok, err = Economy.Transfer(from, to, amount)
	if not ok then
		table.remove(extra.PixLog, table.find(extra.PixLog, entry))
		return false, err
	end
	return true, err
end

-- Remotes (caixa eletrônico e celular): 2 chamadas seguidas, 1 a cada 0,5s
RemoteUtil.BindFunction("BankDeposit", 0.5, 2, function(player, amount)
	if not validAmount(amount) then
		return false, "Invalid"
	end
	return BankService.Deposit(player, amount)
end)

RemoteUtil.BindFunction("BankWithdraw", 0.5, 2, function(player, amount)
	if not validAmount(amount) then
		return false, "Invalid"
	end
	return BankService.Withdraw(player, amount)
end)

RemoteUtil.BindFunction("BankGet", 0.5, 3, function(player)
	return BankService.GetBank(player)
end)

RemoteUtil.BindFunction("Pix", 1, 2, function(player, targetUserId, amount)
	if not RemoteUtil.IsInt(targetUserId, 1) or not validAmount(amount) then
		return false, "Invalid"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return false, "InvalidTarget"
	end
	local ok, res = BankService.Pix(player, target, amount)
	if not ok and res == "PixLimit" then
		RemoteUtil.Flag(player, ("Pix acima do limite (R$%d para %d)"):format(amount, targetUserId))
	end
	return ok, res
end)

return BankService
