# Sessão de teste no Studio (#18, #20, #23, #27, #36, #37, #38)

Este roteiro junta, numa ordem só, os testes no Studio dos PRs:

- **#18**: corridas de mototaxi
- **#20**: lojas e caixa eletrônico do mapa
- **#23**: prisão, cadeia e soltura
- **#27**: trava de sessão do DataStore e save no fechamento (BindToClose)
- **#36**: rate limit e validação de argumentos dos remotes
- **#37**: detecção de salto impossível e bloqueio de 5s das ações físicas
- **#38**: telemetria de segurança, `SecurityQuery` de admin e expulsão por 30 strikes em 60s

Todos já estão na `main`. As partes 1 a 3 levam cerca de 30 a 40 minutos, e as partes 4 a 7 mais uns 40.

## 0. Preparação

1. Atualize a `main` e gere o place. **Sem plugin do Rojo:** usamos só o `setup.sh`.
   ```sh
   git fetch origin
   git checkout main && git pull
   ./setup.sh build   # gera xoblor.rbxl (baixa as ferramentas fixadas, com sha256)
   ```
   No Studio, abra o place em **File > Open from File** e escolha `xoblor.rbxl`.
2. Depois de editar qualquer arquivo em `src/`, rode `./setup.sh build` de novo e reabra o `xoblor.rbxl` no Studio. Não há sincronização ao vivo.
3. Confira que o mapa foi gerado: `Workspace/Map` com os bairros Copacabana, Centro, Zona Norte, Morro e Barra.
4. Servidor local: na aba **Test**, em *Clients and Servers*, escolha **Local Server** com **2 Players** e clique em *Start*. Abre uma janela do servidor e duas de jogador (Player1 e Player2).
   - Na parte 3 (cadeia) precisamos de 3 jogadores (ladrão, vítima e policial). Pare o teste e reinicie com **3 Players** quando chegar lá.
5. Deixe a janela **Output** do servidor aberta: os avisos `[Ride]`, `[Arrest]`, `[Security]` e `[Economy]` aparecem lá.
6. Dinheiro para testar: na janela do servidor (Command Bar, contexto do servidor), rode
   ```lua
   require(game.ServerScriptService.Economy.EconomyService).AddCoins(game.Players.Player1, 5000, "teste")
   ```
   e repita para o Player2.

### Ajustes temporários (desfaça no fim!)

| Onde | Valor padrão | Valor de teste | Para quê |
|---|---|---|---|
| `src/server/Economy/RideLogic.lua`, `RIDE_TIMEOUT` | 300 | 20 | testar a expiração da corrida (passo 1.10) |
| `src/server/Economy/ArrestLogic.lua`, `Config.VICTIM_REFUND` | false | true | testar a devolução às vítimas (passo 3.11) |

Depois de editar, rode `./setup.sh build` e reabra o place. **Antes de encerrar, volte os dois valores e confira com `git status` / `git diff` que não sobrou nada.**

---

## 1. Mototaxi (#18)

Use o Player1.

1. Vá ao `Ponto_Mototaxi` (Morro) e segure "Trabalhar". **Esperado:** você entra no time Mototaxistas e aparece o botão "🏍️ Pegar corrida".
2. Clique em "Pegar corrida". **Esperado:**
   - aparece o aviso "Corrida: leve até Entrega_…";
   - o destino fica destacado em amarelo, com a placa "📍 Entrega_…" visível de longe;
   - o botão vira "✖ Cancelar corrida".
3. Chame `RideStart` de novo pelo console do cliente. **Esperado:** recusa com `RideActive`.
4. Vá até o destino andando ou de moto, levando pelo menos 10s (ou distância/60). **Esperado:**
   - aparece "Corrida paga: +R$ 25" (mais bônus de nível e VIP);
   - o saldo sobe;
   - o destaque some.
5. Logo em seguida, clique em "Pegar corrida". **Esperado:** "Espere um pouco para a próxima". Depois de 15s funciona.
6. Com uma corrida ativa, teleporte até o destino pelo servidor: `HumanoidRootPart.CFrame = <destino>.CFrame`. **Esperado:**
   - "Corrida anulada: chegada rápida demais";
   - nenhum pagamento;
   - aviso `[Ride]`/`[Security]` no Output.
7. Com uma corrida ativa, segure "Trabalhar" no Ponto_Mototaxi para largar o emprego. **Esperado:** "Corrida cancelada", sem pagamento.
8. Com uma corrida ativa, feche a janela do Player1 e entre de novo. **Esperado:** nenhum erro no Output e nenhuma corrida ativa ao voltar.
9. Com uma corrida ativa, resete o personagem. **Esperado:** a corrida continua e o destaque permanece.
10. *(com `RIDE_TIMEOUT = 20`)* Pegue uma corrida e não vá até o destino. **Esperado:** depois de 20s aparece "Corrida expirou", sem pagamento.

## 2. Lojas e caixa eletrônico (#20)

Use o Player1. Se ele ainda for mototaxista, peça demissão no menu.

1. Vá à `Loja_Praia` (Copacabana). **Esperado:** prompt "Abrir loja – Loja Praia" a até ~10 studs.
2. Ative o prompt. **Esperado:** abre o painel "🛒 Loja Praia" só com comida, em ordem de preço.
3. Compre um Açaí. **Esperado:**
   - aparece "Comprado!";
   - a carteira cai R$ 12;
   - a fome e a energia sobem.
4. Com o painel aberto, afaste-se mais de 14 studs e tente comprar. **Esperado:** "Chegue mais perto", sem cobrança.
5. Com a loja de comida aberta, chame pelo console `Remotes.StoreBuy:InvokeServer("fusca")`. **Esperado:** `false, "WrongStore"`.
6. Na `Concessionaria` (Barra), compre a Bicicleta. **Esperado:** ela aparece na garagem do celular.
7. No `Banco_ATM` (Centro), ative o prompt. **Esperado:** "🏧 Banco ATM" com a carteira e o banco corretos.
8. Deposite R$ 10. **Esperado:** a carteira cai R$ 10 e o banco sobe R$ 10.
9. Tente sacar mais do que tem no banco. **Esperado:** "Sem grana", sem mudança.
10. Sem nenhum painel aberto, chame `Remotes.AtmAction:InvokeServer("deposit", 10)`. **Esperado:** `false, "NoSession"`.
11. Clique várias vezes rápido em Depositar. **Esperado:** "Calma aí" depois de 2 cliques.
12. *(opcional, demora)* Deixe o painel aberto por 5 minutos. **Esperado:** "Abra de novo".

## 3. Prisão e cadeia (#23)

Reinicie com **3 Players**: Player1 = A (ladrão), Player2 = B (vítima), Player3 = C (policial). Dê dinheiro a A e B como na preparação.

1. C segura "Trabalhar" na `Delegacia` (Centro). **Esperado:** C entra no time Polícia.
2. A rouba B (aproxime-se a até 8 studs e use o assalto). **Esperado:**
   - A vê "🚨 PROCURADO";
   - B e C veem a placa 🚨 sobre A;
   - só C vê o prompt "Prender" em A.
3. C chega a até 8 studs e segura "Prender". **Esperado:**
   - A vai para a `Cadeia`;
   - A recebe "Preso por …: Ns, multa R$ …" e vê o timer "🔒 PRESO";
   - C recebe 20% da carteira de A;
   - a placa some.
4. C tenta prender A de novo. **Esperado:** "Já está preso" ou "Espere para prender de novo".
5. Preso, A tenta roubar, comprar no menu, comprar numa loja do mapa, fazer Pix e pegar emprego. **Esperado:** tudo recusado ("Você está preso").
6. A sai da cadeia (mais de 15 studs). **Esperado:** volta em até 1s.
7. A reseta o personagem. **Esperado:** renasce na cadeia.
8. Com uns 40s restantes, A sai do jogo, espera 2 a 3 minutos e volta. **Esperado:** volta preso, com os mesmos ~40s. A pena não corre offline.
9. Espere a pena acabar. **Esperado:** "Você foi solto", A aparece na `Saida_Delegacia` e o timer some.
10. C tenta prender alguém que não está procurado, ou que está longe. **Esperado:** "Não está procurado" ou "Chegue mais perto".
11. *(com `VICTIM_REFUND = true`)* Repita os passos 2 e 3 com B online. **Esperado:** B recebe o roubado de volta, limitado ao que sobrou na carteira de A depois da multa.

## Avisos antes das partes 4 a 7

- **UserIds negativos no Local Server.** Em *Clients and Servers* com 2 ou mais players, os jogadores de teste têm UserId negativo (Player1 = -1, Player2 = -2...). Desde o #36, os remotes que recebem o UserId de outro jogador (`RobAttempt`, `Arrest`, `Revive`, `Pix`, `HouseAction` invite) exigem UserId ≥ 1. Por isso, no Local Server, esses remotes chamados pela UI devolvem `Invalid` e geram strike. Isso afeta também o assalto e a prisão da parte 3 (ver "Dúvidas" no PR). Nas partes abaixo, as ações entre jogadores são chamadas direto no módulo do servidor, pela Command Bar do servidor, que não passa pelo remote. **Com o #41**, esse contorno deixa de ser necessário: no Studio (`RunService:IsStudio()`) UserIds negativos passam a ser aceitos, e a UI funciona no Local Server. Em produção continua exigindo UserId ≥ 1, e 0 é recusado nos dois modos.
- **Command Bar.** Cada janela do teste (Server, Player1, Player2) tem a própria Command Bar (View > Command Bar), que roda no contexto daquela janela. "Servidor" e "cliente" abaixo dizem em qual janela rodar.
- **Linha de segurança (#38).** Os eventos aparecem no Output do servidor neste formato:
  `[Security] event=<tipo> userId=<id> context="<remote/sistema>" details="<...>" ts=<os.time> count=<n>`
  Cada combinação (jogador, evento) imprime no máximo **uma linha a cada 10s** (`AdminConfig.LOG_THROTTLE`). Os contadores somam todas as ocorrências, então o `count` da próxima linha impressa pode pular números.

## 4. Trava de sessão e save no fechamento (#27)

**Requisitos:** o DataStore só funciona no Studio com o place **publicado** (File > Publish to Roblox) e com **Game Settings > Security > Enable Studio Access to API Services** ligado. Use um place de teste, não o de produção: os dados são reais (store `EconomyV1`, chave `Player_<UserId>`).

**Por que simular:** no Studio, `game.JobId` é vazio em toda sessão. Por isso, duas sessões do Studio (ou o Team Test, que é edição colaborativa e não dois servidores) não se enxergam como servidores diferentes. Abaixo, a trava de "outro servidor" é simulada escrevendo `SessionJobId = "outro-servidor"` no DataStore. Um teste com dois servidores de verdade só é possível no jogo publicado, entrando em dois servidores diferentes (opcional, ver 4.7).

Use **Play solo (F5)**, que usa o seu UserId real (positivo). Snippets (Command Bar do **servidor**, ou no modo de edição antes do Play):

```lua
-- trava viva de outro servidor (troque 123 pelo seu UserId)
local ds = game:GetService("DataStoreService"):GetDataStore("EconomyV1")
ds:UpdateAsync("Player_123", function(old) old = old or {} old.SessionJobId = "outro-servidor" old.SessionTime = os.time() return old end)
```
```lua
-- trava morta (sem heartbeat há mais de 300s)
ds:UpdateAsync("Player_123", function(old) old = old or {} old.SessionJobId = "outro-servidor" old.SessionTime = os.time() - 301 return old end)
```
```lua
-- ver o registro salvo
print(game:GetService("HttpService"):JSONEncode(ds:GetAsync("Player_123")))
```

1. **Save e liberação normais.** Dê play, ganhe moedas (preparação, passo 6), pare (Stop). Rode o snippet "ver o registro" no modo de edição. **Esperado:** `Coins` atualizado, `Version` = 2, `Jail` = `{"Remaining":0,"Reason":""}`, e **sem** `SessionJobId` (trava liberada).
2. **BindToClose.** Dê play, ganhe moedas e pare **sem** sair do jogador antes. **Esperado:** nenhuma linha `[DataStore] BindToClose terminou com N saves pendentes`. No próximo play, as moedas continuam lá.
3. **Trava viva no login.** No modo de edição, rode o snippet "trava viva" e dê play. **Esperado:** o servidor tenta 5 vezes, com 5s entre elas (cerca de 25s), e expulsa com "Seus dados ainda estão em uso em outro servidor. Tente de novo em instantes." Nada é sobrescrito: o snippet "ver o registro" ainda mostra `SessionJobId = "outro-servidor"`.
4. **Trava morta.** No modo de edição, rode o snippet "trava morta" e dê play. **Esperado:** entra normal, e o Output mostra `[DataStore] trava morta de 123 tomada de outro-servidor`.
5. **Trava perdida durante o jogo.** Com o jogador dentro, rode o snippet "trava viva" na Command Bar do servidor e espere o autosave (até 60s). **Esperado:**
   - expulsão com "Seus dados foram abertos em outro servidor. Entre de novo.";
   - `[Security] event=session_lock_lost userId=123 context="DataStore" details="trava tomada por outro servidor; expulsando" ts=... count=1`.
6. **Falha de DataStore.** Desligue "Enable Studio Access to API Services" e dê play. **Esperado:** linhas `[DataStore] tentativa N falhou: ...`, com espera crescente e aleatória entre elas (até 8s), e depois a expulsão "Falha ao carregar seus dados. Tente novamente." Religue no fim.
7. *(opcional, jogo publicado)* Entre num servidor, e com outra conta ou um servidor privado entre em outro servidor com a mesma conta. **Esperado:** o segundo servidor espera cerca de 25s e expulsa, ou carrega depois que o primeiro salvar e liberar.

**Limpeza:** remova a trava simulada:
```lua
ds:UpdateAsync("Player_123", function(old) if old then old.SessionJobId = nil old.SessionTime = nil end return old end)
```

## 5. Rate limit e validação dos remotes (#36, log do #38)

**Local Server com 2 Players.** Rode na Command Bar do **Player1** (cliente). Os resultados aparecem no Output do Player1, e as linhas `[Security]` no do servidor.

```lua
local R = game.ReplicatedStorage.Remotes
```

1. **Rate limit por remote.** `BankGet` aceita 3 seguidas e recarrega 1 a cada 0,5s.
   ```lua
   for i = 1, 10 do print(i, R.BankGet:InvokeServer()) end
   ```
   **Esperado:** as primeiras devolvem `true <banco>`, e o resto `false RateLimited`. No servidor: `[Security] event=rate_limit userId=-1 context="BankGet" details="" ...`. Rate limit **não** gera strike.
2. **Teto global (todos os remotes juntos).** São 20 seguidas, recarregando 10 por segundo.
   ```lua
   local n = 0 for _, name in {"BankGet","QuitJob","InteractClose","RideCancel","ClaimDaily"} do for i = 1, 6 do local ok, e = R[name]:InvokeServer() if e == "RateLimited" then n += 1 end end end print("recusadas", n)
   ```
   **Esperado:** várias recusadas com `RateLimited`, mesmo misturando remotes.
3. **NaN, infinito, fração, tipo errado e argumento a mais.** Espere 1s entre as linhas por causa do rate limit.
   ```lua
   print(R.BankDeposit:InvokeServer(0/0))        -- false Invalid
   print(R.BankDeposit:InvokeServer(math.huge))  -- false Invalid
   print(R.BankDeposit:InvokeServer(10.5))       -- false Invalid
   print(R.BankDeposit:InvokeServer("10"))       -- false Invalid
   print(R.BankDeposit:InvokeServer(1e13))       -- false Invalid (teto 1e12)
   print(R.BankGet:InvokeServer("extra"))        -- false Invalid (argumento a mais)
   print(R.Pix:InvokeServer(2^60, 10))           -- false Invalid (UserId > 2^53)
   print(R.VehicleAction:InvokeServer("explode"))-- false Invalid
   ```
   **Esperado** no servidor: `[Security] event=invalid_payload userId=-1 context="BankDeposit" details="argumento 1 inválido [strike N]" ...`. Cada chamada inválida é **1 strike**.
4. **Chamada válida continua funcionando.** Abra o ATM e deposite pela UI. **Esperado:** funciona normalmente.
5. *(distância)* A distância do assalto, da prisão e da reanimação é 8 studs (`RemoteGuard.Within`). Posição NaN/inf ou sem personagem é recusada. Pela Command Bar do servidor:
   ```lua
   local Rob = require(game.ServerScriptService.Economy.RobberyService)
   print(Rob.Rob(game.Players.Player1, game.Players.Player2)) -- longe: false TooFar
   ```

**Limpeza:** espere 60s para os strikes zerarem, ou reinicie o teste antes da parte 7.

## 6. Salto impossível e bloqueio de 5s (#37)

**Local Server com 2 Players.** O servidor amostra a posição a cada 0,5s. Pulos, quedas, corrida com WalkSpeed do servidor e veículos (piso de 120 studs/s) são normais.

1. **Andar, pular, cair e dirigir.** Ande, pule de um telhado e dirija a Bicicleta. **Esperado:** nenhuma linha `event=movement_jump`.
2. **Teleporte pelo cliente (exploit).** Na Command Bar do **Player1**:
   ```lua
   local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart
   hrp.CFrame = hrp.CFrame + Vector3.new(300, 0, 0)
   ```
   **Esperado** no servidor (desde o #39): `[Security] event=movement_jump userId=-1 context="Movement" details="jumps=1 block=5s" ts=... count=1`. Nada de kick. Como as outras linhas de segurança, imprime no máximo uma a cada 10s por jogador. O contador soma sempre.
3. **Ações bloqueadas por 5s.** Logo depois do passo 2, aproxime o Player1 do Player2 (até 8 studs) e rode na Command Bar do **servidor**:
   ```lua
   local Eco = game.ServerScriptService.Economy
   print(require(Eco.RobberyService).Rob(game.Players.Player1, game.Players.Player2)) -- false MovementCheck
   print(require(Eco.ArrestService).Arrest(game.Players.Player1, game.Players.Player2)) -- false MovementCheck
   print(require(Eco.MedicService).Revive(game.Players.Player1, game.Players.Player2))   -- false MovementCheck
   print(require(Eco.MovementService).IsBlocked(game.Players.Player1))                   -- true
   ```
   Depois de 5s, `IsBlocked` vira `false` e as ações voltam às regras normais. Por exemplo, `Rob` passa a dar `TargetEmpty`, `Cooldown` etc.
4. **Teleporte do servidor sem liberação também conta.** Na Command Bar do **servidor**:
   ```lua
   local p = game.Players.Player1
   p.Character:PivotTo(p.Character:GetPivot() + Vector3.new(0, 0, 300))
   ```
   **Esperado:** linha `event=movement_jump`. Só os teleportes da lista abaixo são liberados.
5. **Teleportes liberados (sem `event=movement_jump`):**
   - respawn: resete o personagem;
   - casa: entre por uma porta de casa alugada/comprada;
   - cadeia e soltura: prisão pela Command Bar do servidor, com o Player2 procurado e perto: `require(Eco.ArrestService).Arrest(game.Players.Player1, game.Players.Player2)`, com o Player1 policial;
   - hospital: desmaio sem reanimação (#26);
   - manual: `require(Eco.MovementService).AllowTeleport(p)` e logo em seguida o `PivotTo` do passo 4. **Esperado:** sem linha.
6. **WalkSpeed alto setado pelo servidor.** Rode `game.Players.Player1.Character.Humanoid.WalkSpeed = 100` no **servidor** e corra. **Esperado:** sem `event=movement_jump`. Com o mesmo valor setado no **cliente** (não replica), correr gera `event=movement_jump`.

**Observação:** desde o #39 o salto vai para o SecurityLog (`event=movement_jump`) e aparece na consulta de admin da parte 7.

## 7. Telemetria, admin e expulsão (#38)

1. **Não-admin.** Na Command Bar do **Player1**: `print(game.ReplicatedStorage.Remotes.SecurityQuery:InvokeServer())`. **Esperado:** imprime nada (nil). No servidor: `[Security] event=admin_denied userId=-1 context="SecurityQuery" details="" ...`.
2. **Admin.** `AdminConfig.ADMIN_USER_IDS` vem vazio, e UserIds negativos do Local Server nunca são admin. **Com o #41**, dá para pôr `-1` na lista e testar com o Player1 no Local Server, porque negativos valem só no Studio. Sem o #41, para testar:
   - coloque **temporariamente** o seu UserId real em `src/server/Economy/AdminConfig.lua`, rode `./setup.sh build`, reabra e use **Play solo (F5)**;
   - gere alguns eventos (passo 5.1);
   - rode no cliente:
     ```lua
     local ok, data = game.ReplicatedStorage.Remotes.SecurityQuery:InvokeServer()
     print(ok) for uid, ev in data do for name, n in ev do print(uid, name, n) end end
     ```
   **Esperado:** `true`, e depois linhas `<seuUserId> rate_limit N`. Com `InvokeServer(<UserId>)`, só aquele jogador. Os contadores zeram quando o jogador sai.
3. **Expulsão com 30 strikes em 60s.** No Local Server, na Command Bar do **Player1**. O intervalo de 0,55s evita o rate limit, que não conta strike.
   ```lua
   local R = game.ReplicatedStorage.Remotes
   for i = 1, 31 do print(i, R.BankDeposit:InvokeServer(-1)) task.wait(0.55) end
   ```
   **Esperado:**
   - por volta da 30ª chamada (cerca de 17s), o Player1 é expulso com "Atividade suspeita detectada.";
   - no servidor, **antes** da expulsão: `[Security] event=kick userId=-1 context="BankDeposit" details="30 strikes em 60s; último: argumento 1 inválido" ...`;
   - com 29 strikes e espera de mais de 60s, a contagem recomeça e ninguém é expulso.

**Limpeza:** volte `ADMIN_USER_IDS` para vazio (`git diff` limpo) e rode `./setup.sh build` de novo.

## 8. Encerramento

- [ ] `RIDE_TIMEOUT` voltou para 300, `VICTIM_REFUND` voltou para false e `ADMIN_USER_IDS` está vazio (`git diff` vazio).
- [ ] Trava simulada removida do DataStore (limpeza da parte 4) e "Enable Studio Access to API Services" de volta como estava.
- [ ] O Output do servidor não teve erros vermelhos (anote os que aparecerem).

## Checklist para reportar

Copie, marque e cole no PR (ou mande para o Grok Bot). Para cada falha, anote o passo, o que aconteceu e o trecho do Output.

```
Branch/commit testado: main @ <sha>
Mototaxi (#18):   1[ ] 2[ ] 3[ ] 4[ ] 5[ ] 6[ ] 7[ ] 8[ ] 9[ ] 10[ ]
Lojas/ATM (#20):  1[ ] 2[ ] 3[ ] 4[ ] 5[ ] 6[ ] 7[ ] 8[ ] 9[ ] 10[ ] 11[ ] 12[ ]
Cadeia (#23):     1[ ] 2[ ] 3[ ] 4[ ] 5[ ] 6[ ] 7[ ] 8[ ] 9[ ] 10[ ] 11[ ]
DataStore (#27):  1[ ] 2[ ] 3[ ] 4[ ] 5[ ] 6[ ] 7[ ]
Remotes (#36):    1[ ] 2[ ] 3[ ] 4[ ] 5[ ]
Movimento (#37):  1[ ] 2[ ] 3[ ] 4[ ] 5[ ] 6[ ]
Telemetria (#38): 1[ ] 2[ ] 3[ ]
Ajustes temporários revertidos: [ ]
Erros no Output: ...
Observações (valores, sensação de jogo): ...
```
