-- Estado de cadeia: campo de nível superior do perfil, Jail = { EndsAt = os.time() do fim, Reason = "" }.
-- Ausente ou EndsAt = 0 = solto (lido de forma defensiva; schema/migração ficam no DataStoreHandler).
-- Sem dependência de outros serviços, para Job/Shop/Bank/Robbery consultarem sem ciclo de require.
local Data = require(script.Parent.DataStoreHandler)
local ArrestLogic = require(script.Parent.ArrestLogic)

local JailState = {}

function JailState.Left(player)
	return ArrestLogic.Remaining(Data.GetJail(player), os.time())
end

function JailState.IsJailed(player)
	return JailState.Left(player) > 0
end

function JailState.Reason(player)
	return ArrestLogic.Normalize(Data.GetJail(player)).Reason
end

-- Pode fazer `action` ("Rob", "Buy", "Pix", "Job")?
function JailState.Allowed(player, action)
	return ArrestLogic.Allowed(action, JailState.IsJailed(player))
end

-- Atributo replicado para o timer do cliente (fim em os.time()).
local function publish(player)
	local j = ArrestLogic.Normalize(Data.GetJail(player))
	player:SetAttribute("JailEndsAt", j.EndsAt > os.time() and j.EndsAt or nil)
end
JailState.Publish = publish

function JailState.Jail(player, seconds, reason)
	Data.SetJail(player, ArrestLogic.NewJail(os.time(), seconds, reason))
	publish(player)
end

function JailState.Release(player)
	Data.SetJail(player, { EndsAt = 0, Reason = "" })
	publish(player)
end

return JailState
