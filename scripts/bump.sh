#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/bump.sh [patch|minor|major|prepatch|preminor|premajor|prerelease] [--dry-run]

Examples:
  bash scripts/bump.sh patch
  bash scripts/bump.sh minor
  bash scripts/bump.sh prerelease
  bash scripts/bump.sh patch --dry-run
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

BUMP_TYPE="${1:-patch}"
DRY_RUN=0

if [[ "$BUMP_TYPE" == "--dry-run" ]]; then
  BUMP_TYPE="patch"
  DRY_RUN=1
  shift || true
elif [[ $# -gt 0 ]]; then
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

case "$BUMP_TYPE" in
  patch|minor|major|prepatch|preminor|premajor|prerelease)
    ;;
  *)
    echo "Unsupported bump type: $BUMP_TYPE" >&2
    usage
    exit 1
    ;;
esac

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] npm version $BUMP_TYPE --no-git-tag-version"
  exit 0
fi

npm version "$BUMP_TYPE" --no-git-tag-version

echo "Version bumped using '$BUMP_TYPE'."
