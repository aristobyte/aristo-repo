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
  local last_commit_msg
  last_commit_msg="$(git log -1 --pretty=%s 2>/dev/null || true)"

  case "$last_commit_msg" in
    feat*|feature*) echo "minor" ;;
    ref*|refactor*) echo "major" ;;
    fix*|chore*|docs*) echo "patch" ;;
    *) echo "patch" ;;
  esac
}

BUMP_TYPE=""
DRY_RUN=0

if [[ $# -gt 0 && ! "${1:-}" =~ ^-- ]]; then
  BUMP_TYPE="$1"
  shift
fi

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

if [[ -z "$BUMP_TYPE" ]]; then
  BUMP_TYPE="$(auto_detect_bump_type)"
fi

if ! is_valid_type "$BUMP_TYPE"; then
  echo "Unsupported bump type: $BUMP_TYPE" >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "npm version $BUMP_TYPE --no-git-tag-version"
  exit 0
fi

npm version "$BUMP_TYPE" --no-git-tag-version
