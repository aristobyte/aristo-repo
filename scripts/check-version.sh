#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LAST_COMMIT_MSG="$(git log -1 --pretty=%s 2>/dev/null || true)"

case "$LAST_COMMIT_MSG" in
  feat*|feature*) BUMP_TYPE="minor" ;;
  ref*|refactor*) BUMP_TYPE="major" ;;
  fix*|chore*|docs*) BUMP_TYPE="patch" ;;
  *) BUMP_TYPE="patch" ;;
esac

printf "%s\n" "$BUMP_TYPE"
