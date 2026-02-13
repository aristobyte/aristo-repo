#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CACHE_DIR="${NPM_CACHE_DIR:-$ROOT_DIR/.npm-cache}"
mkdir -p "$CACHE_DIR"

DRY_RUN=0
SCOPE="${SCOPE:-NPM}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

case "$SCOPE" in
  NPM|GITHUB_PACKAGES)
    ;;
  *)
    echo "Invalid SCOPE: $SCOPE (expected NPM or GITHUB_PACKAGES)" >&2
    exit 1
    ;;
esac

bash "$ROOT_DIR/scripts/build.sh"

name="$(node -p "require('./package.json').name")"
private="$(node -p "require('./package.json').private===true ? 'true' : 'false'")"
dirname="$(basename "$ROOT_DIR")"

if [[ "$private" == "true" ]]; then
  echo "Skipping private package: $dirname"
  exit 0
fi

if [[ "$SCOPE" == "GITHUB_PACKAGES" ]]; then
  cmd=(npm --cache "$CACHE_DIR" publish --access public --registry https://npm.pkg.github.com/)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    cmd+=(--dry-run)
  fi
  if [[ -n "${NODE_AUTH_TOKEN:-}" ]]; then
    cmd+=(--//npm.pkg.github.com/:_authToken="${NODE_AUTH_TOKEN}")
  elif [[ "$DRY_RUN" -ne 1 ]]; then
    echo "NODE_AUTH_TOKEN is required for GITHUB_PACKAGES publish" >&2
    exit 1
  fi
  echo "Publishing $name to GitHub Packages"
  "${cmd[@]}"
fi

if [[ "$SCOPE" == "NPM" ]]; then
  cmd=(npm --cache "$CACHE_DIR" publish --access public --registry https://registry.npmjs.org/)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    cmd+=(--dry-run)
  fi
  echo "Publishing $name to NPM registry"
  "${cmd[@]}"
fi
