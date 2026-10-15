#!/usr/bin/env bash
# Instala rojo, selene, stylua e lune em versões fixas, verificando o sha256 de cada zip.
# Sem plugins nem actions de terceiros. Versões espelham o rokit.toml.
# Uso: scripts/install-tools.sh [destino]   (padrão: ./.tools)
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${1:-$PWD/.tools}"
mkdir -p "$DEST"

# nome  url  sha256
# selene/stylua/lune: sha256 conferido com o digest publicado pelo GitHub na release.
# rojo 7.4.4: release antiga sem digest publicado; hash calculado em 2026-10-15.
TOOLS=(
  "rojo https://github.com/rojo-rbx/rojo/releases/download/v7.4.4/rojo-7.4.4-linux-x86_64.zip 784e2cd42af3d565826c4910df94f45080fc7ed6206eb6808dbc79b516323652"
  "selene https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-linux.zip d3773393578580074386e69337d35b7acddfbaa9fc38964c07fa3e28436ade9b"
  "lune https://github.com/lune-org/lune/releases/download/v0.11.0/lune-0.11.0-linux-x86_64.zip 5a0ea32c3e13e5e3b1dc415c2056bcfe44258b3a811dcd473c50e3b437d10f72"
  "stylua https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-linux-x86_64.zip a485f72bbfa22e4642e77a84b5edc2611a5cab7477b34e2e709dd8f78e919895"
)

command -v unzip >/dev/null || { echo "Instale o unzip primeiro." >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for entry in "${TOOLS[@]}"; do
  read -r name url sha <<<"$entry"
  if [ -x "$DEST/$name" ] && [ "$(cat "$DEST/.$name.sha256" 2>/dev/null)" = "$sha" ]; then
    continue
  fi
  echo "Baixando $name..."
  curl -fsSL --retry 3 -o "$TMP/$name.zip" "$url"
  echo "$sha  $TMP/$name.zip" | sha256sum -c --quiet - || { echo "sha256 inválido para $name" >&2; exit 1; }
  unzip -o -q "$TMP/$name.zip" "$name" -d "$DEST"
  chmod +x "$DEST/$name"
  echo "$sha" >"$DEST/.$name.sha256"
done
