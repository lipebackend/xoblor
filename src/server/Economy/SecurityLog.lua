-- Telemetria de segurança central: toda suspeita passa por SecurityLog.Record, que
-- grava uma linha estruturada (warn, com throttle) e soma contadores por jogador na sessão.
-- Não expulsa ninguém. Consulta: remote SecurityQuery, só para AdminConfig.ADMIN_USER_IDS.
local Players = game:GetService("Players")
local Logic = require(script.Parent.SecurityLogic)
local Config = require(script.Parent.AdminConfig)

local SecurityLog = {}
local counters = {} -- [userId] = { [event] = n }
local throttle = {}

-- player pode ser Player ou UserId numérico.
function SecurityLog.Record(player, event, context, details)
	local userId = typeof(player) == "Instance" and player.UserId or tonumber(player) or 0
	local n = Logic.Count(counters, userId, event)
	if Logic.ShouldEmit(throttle, userId, event, os.clock(), Config.LOG_THROTTLE) then
		local e = Logic.Entry(event, userId, context, details, os.time())
		warn(Logic.Format(e) .. (" count=%d"):format(n))
	end
	return n
end

function SecurityLog.Counters(userId)
	return Logic.Snapshot(counters, userId)
end

function SecurityLog.IsAdmin(player)
	return typeof(player) == "Instance" and Logic.IsAdmin(Config.ADMIN_USER_IDS, player.UserId)
end

-- Resposta do SecurityQuery: { [userId] = { [event] = n } } de um jogador ou de todos os online.
function SecurityLog.Query(targetUserId)
	local out = {}
	if targetUserId ~= nil and targetUserId ~= "" then
		out[targetUserId] = Logic.Snapshot(counters, targetUserId)
		return out
	end
	for _, p in Players:GetPlayers() do
		out[p.UserId] = Logic.Snapshot(counters, p.UserId)
	end
	return out
end

Players.PlayerRemoving:Connect(function(p)
	Logic.Clear(counters, p.UserId)
	for key in pairs(throttle) do
		if key:sub(1, #tostring(p.UserId) + 1) == tostring(p.UserId) .. ":" then
			throttle[key] = nil
		end
	end
end)

return SecurityLog
