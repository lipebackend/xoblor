-- Regras puras de quem pode receber pelo emprego, testadas com lune em tests/.
-- Afk só vale para o salário periódico (a corrida do mototaxi já exige deslocamento).
-- Jailed = Jail.Remaining > 0 (JailState.IsJailed / ArrestLogic.IsJailed): bloqueia salário e corrida.
local SalaryLogic = {}

-- Retorna nil se pode pagar, senão o motivo ("Jailed" tem prioridade sobre "Afk").
function SalaryLogic.Check(s)
	if s.Jailed then
		return "Jailed"
	end
	if s.Afk then
		return "Afk"
	end
	return nil
end

return SalaryLogic
