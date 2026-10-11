#!/usr/bin/env bash
# Uso: ./setup.sh [serve|build]
#   serve (padrão): sincroniza ao vivo com o Roblox Studio (plugin Rojo)
#   build: gera xoblor.rbxl para abrir no Studio
set -euo pipefail
cd "$(dirname "$0")"

ROJO_VERSION="7.4.4"
BIN_DIR="$PWD/.tools"
ROJO="$BIN_DIR/rojo"

if ! [ -x "$ROJO" ]; then
  command -v unzip >/dev/null || { echo "Instale o unzip primeiro."; exit 1; }
  echo "Baixando Rojo $ROJO_VERSION..."
  mkdir -p "$BIN_DIR"
  curl -fsSL -o /tmp/rojo.zip \
    "https://github.com/rojo-rbx/rojo/releases/download/v$ROJO_VERSION/rojo-$ROJO_VERSION-linux-x86_64.zip"
  unzip -o -q /tmp/rojo.zip -d "$BIN_DIR"
  chmod +x "$ROJO"
  rm -f /tmp/rojo.zip
fi

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
