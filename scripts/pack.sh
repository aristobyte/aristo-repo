#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"

[[ -d "$DIST_DIR" ]] || {
  echo "dist folder is missing; run scripts/compile.sh first" >&2
  exit 1
}

rm -rf "$DIST_DIR/config"
mkdir -p "$DIST_DIR/config"
cp -R "$ROOT_DIR/config/." "$DIST_DIR/config/"

cp "$ROOT_DIR/package.json" "$DIST_DIR/package.json"
cp "$ROOT_DIR/README.md" "$DIST_DIR/README.md"
if [[ -f "$ROOT_DIR/LICENSE" ]]; then
  cp "$ROOT_DIR/LICENSE" "$DIST_DIR/LICENSE"
fi
