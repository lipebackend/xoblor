-- Regras puras de assalto, testadas com lune em tests/.
local RobberyLogic = {}
RobberyLogic.ROB_COOLDOWN = 300
RobberyLogic.PROTECTION = 180
RobberyLogic.WANTED_TIME = 120
RobberyLogic.MIN_PCT, RobberyLogic.MAX_PCT = 10, 30
RobberyLogic.MAX_ROB = 2000
RobberyLogic.MAX_DISTANCE = 8

function RobberyLogic.NormalizeState(s)
	s = type(s) == "table" and s or {}
	s.RobCooldownUntil = tonumber(s.RobCooldownUntil) or 0
	s.ProtectedUntil = tonumber(s.ProtectedUntil) or 0
	s.WantedUntil = tonumber(s.WantedUntil) or 0
	return s
end

-- Checagens que não dependem de posição. Retorna nil se pode, senão o erro.
function RobberyLogic.Check(robberState, targetState, now, robberIsPolice)
	if robberIsPolice then
		return "SameTeamPolice"
	end
	if robberState.RobCooldownUntil > now then
		return "Cooldown"
	end
	if targetState.ProtectedUntil > now then
		return "TargetProtected"
	end
	return nil
end

local MAX_BALANCE = 1e12 -- mesmo teto de EconomyLogic.MAX_BALANCE

-- Valor do assalto: pct da carteira da vítima, até MAX_ROB, e só o que cabe na carteira do ladrão
-- (robberWallet opcional). A vítima perde exatamente esse valor.
function RobberyLogic.Amount(wallet, pct, robberWallet)
	local amount = math.min(math.floor(wallet * pct / 100), RobberyLogic.MAX_ROB)
	if robberWallet ~= nil then
		amount = math.min(amount, math.max(MAX_BALANCE - robberWallet, 0))
	end
	return amount
end

function RobberyLogic.ApplySuccess(robberState, targetState, now)
	robberState.RobCooldownUntil = now + RobberyLogic.ROB_COOLDOWN
	robberState.WantedUntil = now + RobberyLogic.WANTED_TIME
	targetState.ProtectedUntil = now + RobberyLogic.PROTECTION
end

return RobberyLogic
