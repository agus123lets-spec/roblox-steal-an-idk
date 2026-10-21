#!/usr/bin/env bash
# Builds build/NestHeist.rbxl: bakes the map with Lune, then packs everything with Rojo.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
lune run scripts/build-map
rojo build default.project.json --output build/NestHeist.rbxl
echo "Built build/NestHeist.rbxl"
