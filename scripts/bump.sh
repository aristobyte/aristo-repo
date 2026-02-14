#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VALID_TYPES=(patch minor major prepatch preminor premajor prerelease)

is_valid_type() {
  local val="$1"
  for t in "${VALID_TYPES[@]}"; do
    [[ "$t" == "$val" ]] && return 0
  done
  return 1
}

auto_detect_bump_type() {
  bash "$ROOT_DIR/scripts/check-version.sh"
}

BUMP_TYPE=""

if [[ $# -gt 0 && ! "${1:-}" =~ ^-- ]]; then
  BUMP_TYPE="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  echo "Unknown option: $1" >&2
  exit 1
  shift
done

if [[ -z "$BUMP_TYPE" ]]; then
  BUMP_TYPE="$(auto_detect_bump_type)"
fi

if ! is_valid_type "$BUMP_TYPE"; then
  echo "Unsupported bump type: $BUMP_TYPE" >&2
  exit 1
fi

npm version "$BUMP_TYPE" --no-git-tag-version
