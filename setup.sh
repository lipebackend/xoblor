#!/usr/bin/env bash
# Uso: ./setup.sh [serve|build]
#   serve (padrão): sincroniza ao vivo com o Roblox Studio (plugin Rojo)
#   build: gera xoblor.rbxl para abrir no Studio
set -euo pipefail
cd "$(dirname "$0")"

BIN_DIR="$PWD/.tools"
ROJO="$BIN_DIR/rojo"

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
  *) echo "Uso: $0 [serve|build]"; exit 1 ;;
esac
