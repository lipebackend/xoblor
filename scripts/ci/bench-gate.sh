#!/usr/bin/env bash
# Gate de desempenho do CI (docs/BENCH.md, "No CI").
#  1) p95 de todos os cenários com 30 jogadores <= 1 ms
#  2) max do autosave escalonado com 60 jogadores <= 0,5 ms
# Runner compartilhado tem ruído (vizinhos, GC, agendador): cada checagem roda até
# ATTEMPTS vezes em processos separados e só falha se TODAS as tentativas estourarem.
# Código 3 (AutosaveSchedule ausente) falha na hora, sem nova tentativa.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

ATTEMPTS="${BENCH_ATTEMPTS:-3}"
P95_MS="${BENCH_P95_MS:-1}"
STAGGER_MAX_MS="${BENCH_STAGGER_MAX_MS:-0.5}"

check() {
  local name="$1"; shift
  local i code
  for i in $(seq 1 "$ATTEMPTS"); do
    echo "::group::$name (tentativa $i/$ATTEMPTS)"
    lune run bench/run.luau "$@" --ci
    code=$?
    echo "::endgroup::"
    if [ "$code" -eq 0 ]; then
      echo "OK: $name passou na tentativa $i"
      return 0
    fi
    if [ "$code" -eq 3 ]; then
      echo "::error::$name: AutosaveSchedule ausente (código 3)"
      return 3
    fi
    echo "::warning::$name: tentativa $i estourou o limite (código $code)"
  done
  echo "::error::$name: estourou o limite em todas as $ATTEMPTS tentativas"
  return 1
}

status=0
check "p95 com 30 jogadores (<= ${P95_MS} ms)" 30 2000 "--p95-ms=$P95_MS" || status=1
check "max do autosave escalonado com 60 jogadores (<= ${STAGGER_MAX_MS} ms)" 60 2400 \
  --only-stagger --no-p95 "--stagger-max-ms=$STAGGER_MAX_MS" || status=1
exit "$status"
