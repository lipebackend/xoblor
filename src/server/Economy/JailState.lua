-- Estado de cadeia: campo de nível superior do perfil, Jail = { Remaining = segundos, Reason = "" }.
-- A pena só corre online (ArrestService desconta a cada segundo). Ausente ou Remaining = 0 = solto;
-- o campo legado EndsAt é ignorado. O valor é salvo pelo caminho normal do DataStoreHandler
-- (saída, autosave e BindToClose).
-- Sem dependência de outros serviços, para Job/Shop/Bank/Robbery consultarem sem ciclo de require.
local Data = require(script.Parent.DataStoreHandler)
local ArrestLogic = require(script.Parent.ArrestLogic)

local JailState = {}

function JailState.Left(player)
	return ArrestLogic.Remaining(Data.GetJail(player))
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

-- Atributo replicado para o timer do cliente (segundos restantes).
local function publish(player)
	local left = JailState.Left(player)
	player:SetAttribute("JailLeft", left > 0 and left or nil)
end
JailState.Publish = publish

function JailState.Jail(player, seconds, reason)
	Data.SetJail(player, ArrestLogic.NewJail(seconds, reason))
	publish(player)
end

-- Desconta dt segundos online. Retorna true se a pena acabou agora.
function JailState.Tick(player, dt)
	local jail, done = ArrestLogic.Tick(Data.GetJail(player), dt)
	Data.SetJail(player, jail)
	publish(player)
	return done
end

function JailState.Release(player)
	Data.SetJail(player, { Remaining = 0, Reason = "" })
	publish(player)
end

return JailState
