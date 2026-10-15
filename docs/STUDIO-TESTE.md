# Sessão de teste no Studio (#18, #20, #23)

Este roteiro junta, numa ordem só, os testes no Studio dos PRs:

- **#18**: corridas de mototaxi
- **#20**: lojas e caixa eletrônico do mapa
- **#23**: prisão, cadeia e soltura

Dá para fazer tudo de uma vez, em cerca de 30 a 40 minutos.

## 0. Preparação

1. Carregue o branch que tem os três PRs:
   ```sh
   git fetch origin
   git checkout feat/prisao   # contém #18 + #20 + #23
   ```
2. Instale as ferramentas (`rokit install`) e rode `rojo serve`. No Studio, abra um place vazio e conecte pelo plugin do Rojo (Connect).
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

O `rojo serve` aplica as mudanças na hora; reinicie o teste depois de editar. **Antes de encerrar, volte os dois valores e confira com `git status` / `git diff` que não sobrou nada.**

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

## 4. Encerramento

- [ ] `RIDE_TIMEOUT` voltou para 300 e `VICTIM_REFUND` voltou para false (`git diff` vazio).
- [ ] O Output do servidor não teve erros vermelhos (anote os que aparecerem).

## Checklist para reportar

Copie, marque e cole no PR (ou mande para o Grok Bot). Para cada falha, anote o passo, o que aconteceu e o trecho do Output.

```
Branch/commit testado: feat/prisao @ <sha>
Mototaxi (#18):   1[ ] 2[ ] 3[ ] 4[ ] 5[ ] 6[ ] 7[ ] 8[ ] 9[ ] 10[ ]
Lojas/ATM (#20):  1[ ] 2[ ] 3[ ] 4[ ] 5[ ] 6[ ] 7[ ] 8[ ] 9[ ] 10[ ] 11[ ] 12[ ]
Cadeia (#23):     1[ ] 2[ ] 3[ ] 4[ ] 5[ ] 6[ ] 7[ ] 8[ ] 9[ ] 10[ ] 11[ ]
Ajustes temporários revertidos: [ ]
Erros no Output: ...
Observações (valores, sensação de jogo): ...
```
