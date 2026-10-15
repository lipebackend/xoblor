-- Fechamento do servidor (BindToClose), regras puras testadas com lune em tests/.
-- Dispara o save de saída de todos os jogadores EM PARALELO (env.spawn), com um prazo comum,
-- e volta assim que todos terminarem ou o prazo acabar. env: clock, wait, spawn, busy (opcional).
local DataStoreClose = {}

DataStoreClose.POLL = 0.1

-- saveOne(player, deadline) deve respeitar o prazo (DataStoreRetry faz isso).
-- Retorna quantos saves ainda estavam pendentes e o prazo usado.
function DataStoreClose.Run(players, saveOne, env, timeout)
	local deadline = env.clock() + timeout
	local pending = 0
	for _, p in players do
		pending += 1
		env.spawn(function()
			saveOne(p, deadline)
			pending -= 1
		end)
	end
	while (pending > 0 or (env.busy and env.busy())) and env.clock() < deadline do
		env.wait(math.min(DataStoreClose.POLL, deadline - env.clock()))
	end
	return pending, deadline
end

return DataStoreClose
