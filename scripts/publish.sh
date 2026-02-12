#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CACHE_DIR="${NPM_CACHE_DIR:-$ROOT_DIR/.npm-cache}"
mkdir -p "$CACHE_DIR"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/publish.sh [--dry-run] [--tag TAG] [--otp CODE] [--access public|restricted]

Examples:
  bash scripts/publish.sh --dry-run
  bash scripts/publish.sh --tag next
  bash scripts/publish.sh --otp 123456
USAGE
}

DRY_RUN=0
TAG=""
OTP=""
ACCESS="public"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --tag)
      shift
      [[ $# -gt 0 ]] || { echo "--tag requires a value" >&2; exit 1; }
      TAG="$1"
      ;;
    --otp)
      shift
      [[ $# -gt 0 ]] || { echo "--otp requires a value" >&2; exit 1; }
      OTP="$1"
      ;;
    --access)
      shift
      [[ $# -gt 0 ]] || { echo "--access requires a value" >&2; exit 1; }
      ACCESS="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

case "$ACCESS" in
  public|restricted)
    ;;
  *)
    echo "Invalid --access value: $ACCESS" >&2
    exit 1
    ;;
esac

bash "$ROOT_DIR/scripts/build.sh"

cmd=(npm --cache "$CACHE_DIR" publish --access "$ACCESS")
[[ -n "$TAG" ]] && cmd+=(--tag "$TAG")
[[ -n "$OTP" ]] && cmd+=(--otp "$OTP")
[[ "$DRY_RUN" -eq 1 ]] && cmd+=(--dry-run)

printf 'Running: '
printf '%q ' "${cmd[@]}"
echo

"${cmd[@]}"

echo "Publish completed."
