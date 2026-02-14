#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCOPE="${SCOPE:-}"

while [[ $# -gt 0 ]]; do
  echo "Unknown option: $1" >&2
  exit 1
  shift
done

name="$(node -p "require('./package.json').name")"
private="$(node -p "require('./package.json').private===true ? 'true' : 'false'")"
dirname="$(basename "$ROOT_DIR")"

if [[ "$private" == "true" ]]; then
  echo "Skipping private package: $dirname"
  exit 0
fi

if [[ "$SCOPE" == "GITHUB_PACKAGES" ]]; then
  echo "Publishing $name to GitHub Packages"
  npm publish \
    --access public \
    --registry https://npm.pkg.github.com/ \
    --//npm.pkg.github.com/:_authToken=$NODE_AUTH_TOKEN
  exit 0
fi

if [[ "$SCOPE" == "NPM" ]]; then
  echo "Publishing $name to NPM registry"
  npm publish \
    --access public \
    --registry https://registry.npmjs.org/ \
    --scope=@aristobyte \
    --//registry.npmjs.org/:_authToken=$NODE_AUTH_TOKEN
  exit 0
fi

echo "Invalid SCOPE: $SCOPE (expected NPM or GITHUB_PACKAGES)" >&2
exit 1