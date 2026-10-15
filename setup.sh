#!/usr/bin/env bash
# Uso: ./setup.sh [serve|build|bench]
#   serve (padrão): sincroniza ao vivo com o Roblox Studio (plugin Rojo)
#   build: gera xoblor.rbxl para abrir no Studio
#   bench [jogadores] [ticks] [--ci ...]: benchmark de carga com lune (docs/BENCH.md)
set -euo pipefail
cd "$(dirname "$0")"

BIN_DIR="$PWD/.tools"
ROJO="$BIN_DIR/rojo"

if [ "${1:-}" = "bench" ]; then
  shift
  exec lune run bench/run.luau "$@"
fi

# Baixa rojo/selene/stylua fixados com verificação de sha256.
./scripts/install-tools.sh "$BIN_DIR"

case "${1:-serve}" in
  build)
    "$ROJO" build default.project.json -o xoblor.rbxl
    echo "Pronto: abra xoblor.rbxl no Roblox Studio."
    ;;
  serve)
    "$ROJO" plugin install || echo "Instale o plugin Rojo manualmente no Studio, se necessário."
    echo "No Studio: aba Plugins > Rojo > Connect."
    "$ROJO" serve default.project.json
    ;;
  *) echo "Uso: $0 [serve|build|bench]"; exit 1 ;;
esac
