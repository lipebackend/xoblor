-- Estado de desmaio, só em memória (não é salvo: quem volta ao jogo está acordado).
-- Sem dependências, para JailState/Robbery/Medic consultarem sem ciclo de require.
local Players = game:GetService("Players")

local DownState = {}
local downed = {} -- [player] = { At = os.clock() }

function DownState.Get(player)
	return downed[player]
end

function DownState.IsDowned(player)
	return downed[player] ~= nil
end

function DownState.Set(player, info)
	downed[player] = info
	player:SetAttribute("Downed", info ~= nil or nil)
end

Players.PlayerRemoving:Connect(function(p)
	downed[p] = nil
end)

return DownState
