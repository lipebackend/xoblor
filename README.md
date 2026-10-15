int project

## Desenvolvimento

As ferramentas (Rojo, selene, StyLua) estão fixadas em `rokit.toml`. Com o [Rokit](https://github.com/rojo-rbx/rokit) instalado:

```bash
rokit install                                  # instala as versões do projeto
stylua src                                     # formata o código
stylua --check src                             # só verifica a formatação (como no CI)
selene src                                     # lint (std = roblox)
rojo build default.project.json -o xoblor.rbxl # gera o place
rojo serve default.project.json                # sincroniza com o Studio
```

Sem Rokit, `./setup.sh [serve|build]` baixa só o Rojo.

## Admin (telemetria de segurança)

O servidor registra suspeitas (rate limit, payload inválido, trava de sessão perdida, corrida suspeita, Pix acima do limite, expulsão) em uma linha `[Security] event=... userId=...` no log e soma contadores por jogador durante a sessão.

Só os UserIds de `src/server/Economy/AdminConfig.lua` podem consultar esses contadores. A lista vem vazia.

1. Descubra o UserId: é o número na URL do perfil (`https://www.roblox.com/users/123456789/profile`). Com o jogador no jogo, também dá para rodar `print(game.Players.Fulano.UserId)` na barra de comandos do Studio.
2. Adicione o número em `ADMIN_USER_IDS`:
   ```lua
   ADMIN_USER_IDS = {
   	123456789, -- Fulano
   },
   ```
3. Abra um PR, gere o place (`./setup.sh build` ou a release `latest`) e publique.
4. No jogo, como admin, abra o console do desenvolvedor (F9) e rode na aba do cliente:
   ```lua
   print(game.ReplicatedStorage.Remotes.SecurityQuery:InvokeServer())            -- todos os online
   print(game.ReplicatedStorage.Remotes.SecurityQuery:InvokeServer(123456789))   -- um jogador
   ```
   Quem não é admin não recebe nada, e a tentativa fica registrada como `admin_denied`.

## CI e release

- **CI** (`.github/workflows/ci.yml`): em push e PR para `main`, roda StyLua, selene e o build com Rojo; o `xoblor.rbxl` fica como artefato da execução.
- **CodeQL** (`codeql.yml`): analisa a segurança dos workflows do GitHub Actions.
- **Dependabot**: atualiza as actions semanalmente.
- **Release**: crie e envie uma tag para gerar a GitHub Release com o `xoblor.rbxl` anexado:

```bash
git tag v0.1.0
git push origin v0.1.0
```
