-- Regras puras de desmaio e atendimento médico, testadas com lune em tests/.
local MedicLogic = {}

-- Todos os padrões ficam aqui; mude só esta tabela para ajustar.
MedicLogic.Config = {
	FAINT_AFTER = 30, -- segundos com fome OU energia em 0 até desmaiar
	BLEEDOUT = 90, -- segundos desmaiado até ir sozinho ao hospital
	HOSPITAL_FEE = 100, -- cobrado na ida ao hospital (vai para a "casa", some da economia)
	REVIVE_FEE = 50, -- pago pelo paciente ao médico que reanimou
	REVIVE_DISTANCE = 8, -- studs entre médico e paciente
	REVIVE_COOLDOWN = 10, -- segundos entre reanimações do mesmo médico
	RESTORE_NEEDS = 30, -- fome e energia depois de reanimar ou do hospital
	ROB_DOWNED = false, -- desmaiado pode ser assaltado?
	CALL_INTERVAL = 30, -- "Chamar médico": 1 chamada a cada N segundos
	-- o que o desmaiado não pode fazer
	BLOCKED = { Rob = true, Buy = true, Pix = true, Job = true },
}

local function num(n)
	n = tonumber(n)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return n
end

-- Acompanha o tempo com necessidade zerada. Retorna novo zeroSince (ou nil) e se deve desmaiar agora.
-- needZero: fome ou energia em 0. jailed/downed: preso não desmaia; já desmaiado não desmaia de novo.
function MedicLogic.FaintStep(zeroSince, needZero, jailed, downed, now, cfg)
	cfg = cfg or MedicLogic.Config
	if jailed or downed or not needZero then
		return nil, false
	end
	zeroSince = zeroSince or now
	return zeroSince, now - zeroSince >= cfg.FAINT_AFTER
end

-- Segundos até o hospital automático.
function MedicLogic.BleedoutLeft(downedAt, now, cfg)
	cfg = cfg or MedicLogic.Config
	return math.max(0, cfg.BLEEDOUT - (now - num(downedAt)))
end

-- Taxa limitada à carteira (inteiro, nunca negativa).
function MedicLogic.Fee(fee, wallet)
	return math.max(0, math.min(math.floor(num(fee)), math.floor(num(wallet))))
end

-- Quanto somar para levar a necessidade até RESTORE_NEEDS (nunca baixa quem já está acima).
function MedicLogic.RestoreDelta(current, cfg)
	cfg = cfg or MedicLogic.Config
	return math.max(0, cfg.RESTORE_NEEDS - math.floor(num(current)))
end

-- nil se pode reanimar, senão o código do erro.
-- a = { IsMedic, MedicDowned, MedicJailed, CooldownUntil, TargetDowned, Distance, Now }
function MedicLogic.CanRevive(a, cfg)
	cfg = cfg or MedicLogic.Config
	if not a.IsMedic then
		return "NotMedic"
	end
	if a.MedicDowned then
		return "Downed"
	end
	if a.MedicJailed then
		return "Jailed"
	end
	if num(a.CooldownUntil) > a.Now then
		return "Cooldown"
	end
	if not a.TargetDowned then
		return "NotDowned"
	end
	if type(a.Distance) ~= "number" or a.Distance ~= a.Distance or a.Distance > cfg.REVIVE_DISTANCE then
		return "TooFar"
	end
	return nil
end

function MedicLogic.Allowed(action, downed, cfg)
	cfg = cfg or MedicLogic.Config
	return not (downed and cfg.BLOCKED[action])
end

function MedicLogic.CanBeRobbed(downed, cfg)
	cfg = cfg or MedicLogic.Config
	return not downed or cfg.ROB_DOWNED == true
end

return MedicLogic
