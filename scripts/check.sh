#!/usr/bin/env bash
# One-command quality gate: type-check against the real Roblox API, run the
# headless logic tests, and build the place file.
#   ./scripts/check.sh           -> build/BeastValley.rbxlx
# Tools are downloaded once into .tools/ (Linux x86_64).
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS=.tools
mkdir -p "$TOOLS" build

fetch() { # url zip-member
  local url=$1 bin=$2
  if [ ! -x "$TOOLS/$bin" ]; then
    curl -sSL -o "$TOOLS/tmp.zip" "$url"
    unzip -o -q "$TOOLS/tmp.zip" -d "$TOOLS"
    rm "$TOOLS/tmp.zip"
    chmod +x "$TOOLS/$bin"
  fi
}
fetch https://github.com/rojo-rbx/rojo/releases/download/v7.4.4/rojo-7.4.4-linux-x86_64.zip rojo
fetch https://github.com/JohnnyMorganz/luau-lsp/releases/latest/download/luau-lsp-linux-x86_64.zip luau-lsp
fetch https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip luau
[ -f "$TOOLS/globalTypes.d.luau" ] || curl -sSL -o "$TOOLS/globalTypes.d.luau" \
  https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau

echo "== type check"
"$TOOLS/rojo" sourcemap default.project.json -o "$TOOLS/sourcemap.json"
out=$("$TOOLS/luau-lsp" analyze --definitions="$TOOLS/globalTypes.d.luau" \
  --sourcemap="$TOOLS/sourcemap.json" src 2>&1 | grep -v '^\[INFO\]\|didChangeWatchedFiles' || true)
if [ -n "$out" ]; then echo "$out"; exit 1; fi
echo "clean"

echo "== logic tests"
LUAU="$TOOLS/luau" python3 tests/run.py

echo "== build"
"$TOOLS/rojo" build default.project.json -o build/BeastValley.rbxlx
