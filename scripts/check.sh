#!/usr/bin/env bash
# Lint, format check, Roblox type-check and Lune tests. Run scripts/build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

LUAU_LSP_VERSION="1.70.1"
TYPES="build/types/globalTypes.None.d.luau"
if [ ! -f "$TYPES" ]; then
	mkdir -p build/types
	curl -sSfL -o "$TYPES" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${LUAU_LSP_VERSION}/scripts/globalTypes.None.d.luau"
fi

echo "== stylua"
stylua --check src scripts tests
echo "== selene"
selene src
echo "== luau-lsp analyze"
rojo sourcemap default.project.json --output sourcemap.json
# Pass 1: full project with the sourcemap (cross-module types; services are annotated explicitly).
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions "@roblox=$TYPES" src
# Pass 2: without the sourcemap `game`/`workspace` keep their API types; fail on any member error there.
if luau-lsp analyze --definitions "@roblox=$TYPES" src 2>&1 | grep -E "external type '(Workspace|DataModel)'"; then
	echo "workspace/game API misuse found"
	exit 1
fi
echo "== lune tests"
lune run tests/logic.spec
lune run tests/place.spec
echo "All checks passed"
