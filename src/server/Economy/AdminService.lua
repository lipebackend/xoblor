-- Consulta da telemetria de segurança para admins (AdminConfig.ADMIN_USER_IDS).
-- Uso (console do desenvolvedor, como admin):
--   game.ReplicatedStorage.Remotes.SecurityQuery:InvokeServer()          -- todos os online
--   game.ReplicatedStorage.Remotes.SecurityQuery:InvokeServer(123456789) -- um jogador
-- Não-admin não recebe nada (nil) e a tentativa é registrada como admin_denied.
local RemoteUtil = require(script.Parent.RemoteUtil)
local SecurityLog = require(script.Parent.SecurityLog)

RemoteUtil.BindFunction("SecurityQuery", function(player, targetUserId)
	if not SecurityLog.IsAdmin(player) then
		SecurityLog.Record(player, "admin_denied", "SecurityQuery", "")
		return nil
	end
	return true, SecurityLog.Query(targetUserId)
end)

return {}
