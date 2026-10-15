# Benchmark de carga (lune)

Mede quanto custa, por tick do servidor, a lógica de segurança e de save com N jogadores simulados.
O CI roda um gate com limites (ver "No CI" abaixo). Rode à mão antes de mexer em `MoveLogic`, `RemoteGuard`, `SecurityLogic` ou `ProfileLogic`.

```bash
./setup.sh bench              # 30 jogadores, 2000 ticks
./setup.sh bench 60 1000      # jogadores, ticks
lune run bench/run.luau 30    # o mesmo, sem o setup.sh
```

## O que é medido

1 tick = 0,5 s de jogo, que é o intervalo de amostragem do `MovementService`. Há 200 ticks de aquecimento, descartados. O relatório mostra a mediana, o p95, o p99, o máximo e a média em ms por tick. A meta é **p95 < 1 ms com 30 jogadores**.

| Cenário | O que roda por tick |
|---|---|
| movimento | `MoveLogic.MaxSpeed` + `MoveLogic.Sample` por jogador (andar aleatório; 1 jogador teleporta em 5% dos ticks → `movement_jump` no log) |
| remotes | por jogador, 1–2 chamadas (mix BankDeposit/Pix/House/Rob/Arrest); 2 abusadores com 15 chamadas e 1/3 de payload inválido (NaN, U+2028). Cada chamada: token bucket global + por remote (`RemoteGuard.Take`), `RemoteGuard.Check` com os schemas reais, e `SecurityLogic` Count/ShouldEmit/Entry/Format quando recusada; `MoveLogic.IsBlocked` |
| autosave | para todos: `UpdateAsync` num DataStore falso, ou seja, decodifica o JSON antigo, roda `ProfileLogic.BuildSave` e codifica o novo (`@lune/serde`) |
| autosave só lógica | só `BuildSave`, sem o JSON |
| tick normal | movimento + remotes |
| tick com autosave | movimento + remotes + autosave de todos **em todo tick**. É o pior caso: no jogo, o autosave roda a cada 60 s (120 ticks) |

Antes do autosave, todos os perfis são carregados uma vez (`LockDecision` + `Migrate`).

## Resultado de exemplo

Máquina: VM Linux com Intel Xeon (8 vCPU), lune 0.11.0, 15/10/2026. Os valores estão em ms por tick.

30 jogadores:

| cenário | mediana | p95 | p99 | max |
|---|---|---|---|---|
| movimento | 0.0068 | 0.0154 | 0.0186 | 0.0278 |
| remotes | 0.0406 | 0.0644 | 0.0781 | 0.1034 |
| autosave (com JSON) | 0.3638 | 0.4773 | 0.5830 | 0.7160 |
| autosave só lógica | 0.0125 | 0.0268 | 0.0374 | 0.0599 |
| tick normal | 0.0542 | 0.0860 | 0.1204 | 0.1711 |
| tick com autosave | 0.4042 | 0.5071 | 0.7201 | 1.5632 |

Com 60 jogadores, o tick normal fica em p95 ≈ 0,11 ms e o tick com autosave em p95 ≈ 0,95 ms.

Tudo ficou abaixo da meta, então nenhuma otimização foi necessária. Do custo do autosave, ~95% é a (de)serialização JSON do mock. No Roblox, essa serialização acontece no `UpdateAsync`, em C++ e fora do script, e a chamada é assíncrona, sem bloquear o tick. O custo que é nosso (`BuildSave`) fica abaixo de 0,03 ms no p95.

O max às vezes tem picos isolados de 1 a 50 ms. São coleta de lixo e agendamento do SO na VM, não se repetem e não aparecem no p95/p99.

## Autosave: todos no mesmo tick x escalonado (#43)

Dois cenários rodam movimento + remotes em todo tick e incluem o autosave na cadência real, com cada jogador salvando a cada 60 s (120 ticks):

- **antes:** todos os jogadores salvam juntos a cada 120 ticks, como o `DataStoreHandler` fazia antes do #43;
- **depois:** cada jogador salva na sua fase do `AutosaveSchedule`, o módulo do #43.

O cenário "depois" só roda se `src/server/Economy/AutosaveSchedule.lua` existir. Sem ele, o bench avisa e pula o cenário.

Como só 1 tick em 120 tem save, o efeito aparece no **max**, que é o pior tick. A mediana e o p95 quase não mudam. Medição com 2400 ticks (20 ciclos de autosave), na mesma máquina, em ms por tick:

| jogadores | cenário | mediana | p95 | p99 | max |
|---|---|---|---|---|---|
| 30 | antes (todos juntos) | 0.0538 | 0.0746 | 0.1187 | 0.5666 |
| 30 | depois (escalonado) | 0.0553 | 0.0805 | 0.1025 | **0.1596** |
| 60 | antes (todos juntos) | 0.0848 | 0.1268 | 0.1897 | 1.2394 |
| 60 | depois (escalonado) | 0.0953 | 0.1335 | 0.1635 | **0.2001** |

O pior tick cai de ~0,57 para ~0,16 ms com 30 jogadores, e de ~1,24 para ~0,20 ms com 60. Com 60 jogadores, o "antes" passa da meta de 1 ms. A mediana sobe ~0,01 ms por causa do `Schedule.Due` a cada tick.

No jogo, o ganho maior está fora do script: o orçamento de `UpdateAsync` deixa de receber 30 a 60 requisições no mesmo segundo.

## No CI

O job **Bench (lune)** roda `scripts/ci/bench-gate.sh`, que faz duas checagens:

1. **p95 ≤ 1 ms** em todos os cenários, com 30 jogadores e 2000 ticks;
2. **max ≤ 0,5 ms** no cenário de autosave escalonado, com 60 jogadores e 2400 ticks (`--only-stagger`).

Tratamento do ruído do runner:

- cada execução descarta 200 ticks de aquecimento;
- cada checagem roda até **3 vezes**, em processos separados (GC e heap novos), e **só falha se as 3 estourarem**.

O max é um único tick e sofre picos isolados de GC e agendamento. Uma tentativa boa basta para mostrar que o código cabe no limite. Uma regressão real estoura em todas as tentativas.

Os limites e o número de tentativas podem ser trocados por variáveis de ambiente: `BENCH_P95_MS`, `BENCH_STAGGER_MAX_MS` e `BENCH_ATTEMPTS`.

O bench também tem flags para uso direto:

```bash
lune run bench/run.luau 30 2000 --ci --p95-ms=1
lune run bench/run.luau 60 2400 --ci --only-stagger --no-p95 --stagger-max-ms=0.5
```

Com `--ci` (ou `XOBLOR_BENCH_CI=1`), o bench imprime uma linha `BENCH_RESULT {json}` por cenário e sai com um destes códigos:

- `0`: ok;
- `1`: p95 estourou;
- `2`: max do escalonado estourou;
- `3`: `--stagger-max-ms` foi pedido, mas `src/server/Economy/AutosaveSchedule.lua` não existe. Isso **falha na hora, sem nova tentativa**: tirar o escalonamento é regressão, não ruído.

Sem `--ci`, `./setup.sh bench` funciona como antes e sempre sai com 0.

## Limitações (lune ≠ Roblox)

- O lune roda Luau com o mesmo compilador, mas sem o codegen nativo (`--!native`) e com outro GC e outro agendador. No servidor Roblox, os números absolutos podem ser diferentes. O que vale é a ordem de grandeza e a comparação antes/depois.
- As posições são tabelas `{X, Y, Z}`, não `Vector3`. Leituras de `HumanoidRootPart.Position`, `Players:GetPlayers()`, rede/replicação e o `warn` no Output não entram no bench.
- O DataStore é um mock em memória: sem latência, sem orçamento de requisições e sem retry. O tempo real de um save é dominado pela rede e não bloqueia o tick.
- O `os.clock()` tem resolução de microssegundos. Por isso, valores abaixo de ~0,005 ms são ruído.
