-- Administradores (só servidor; o cliente não vê este arquivo). Lista vazia = ninguém é admin.
-- Admin pode consultar a telemetria de segurança pelo remote SecurityQuery (ver README, "Admin").
--
-- Como adicionar: coloque o UserId (número, não o nome) na lista e publique o jogo de novo.
-- Onde achar o UserId: no perfil roblox.com/users/<UserId>/profile (o número na URL),
-- ou no Studio, com o jogador no jogo: print(game.Players.<Nome>.UserId) na barra de comandos.
return {
	ADMIN_USER_IDS = {
		-- 123456789, -- exemplo: Fulano (dono do jogo)
	},
	LOG_THROTTLE = 10, -- segundos entre linhas repetidas do mesmo (jogador, evento) no console
}
