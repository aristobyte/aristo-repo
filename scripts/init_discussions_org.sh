#!/usr/bin/env bash
set -euo pipefail

# Apply discussions template to all repos in an org (or filtered set).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/init_discussions_org.sh --org ORG [options]

Options:
  --config FILE       Config path (default: ./config/discussions.config.json)
  --allow-private     Include private repos
  --include-archived  Include archived repos
  --max-repos N       Limit repos processed
  --dry-run           Print actions only
  -h, --help          Show help
USAGE
}

ORG=""
CONFIG_FILE="./config/discussions.config.json"
ALLOW_PRIVATE=0
INCLUDE_ARCHIVED=0
MAX_REPOS=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      shift
      [[ $# -gt 0 ]] || { echo "--org requires value" >&2; exit 1; }
      ORG="$1"
      ;;
    --config)
      shift
      [[ $# -gt 0 ]] || { echo "--config requires value" >&2; exit 1; }
      CONFIG_FILE="$1"
      ;;
    --allow-private)
      ALLOW_PRIVATE=1
      ;;
    --include-archived)
      INCLUDE_ARCHIVED=1
      ;;
    --max-repos)
      shift
      [[ $# -gt 0 ]] || { echo "--max-repos requires value" >&2; exit 1; }
      MAX_REPOS="$1"
      [[ "$MAX_REPOS" =~ ^[0-9]+$ ]] || { echo "--max-repos must be non-negative integer" >&2; exit 1; }
      ;;
    --dry-run)
      DRY_RUN=1
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

[[ -n "$ORG" ]] || { echo "--org is required" >&2; usage; exit 1; }

REPO_SCRIPT="$SCRIPT_DIR/init_discussions_repo.sh"
[[ -x "$REPO_SCRIPT" ]] || { echo "Missing executable: $REPO_SCRIPT" >&2; exit 1; }

common_require_gh_jq

common_check_gh_auth

seen=0
applied=0
skipped=0
failed=0

while IFS= read -r line; do
  name="${line%%$'\t'*}"
  rest="${line#*$'\t'}"
  visibility="${rest%%$'\t'*}"
  archived="${rest##*$'\t'}"

  seen=$((seen + 1))
  if [[ -n "$MAX_REPOS" && "$seen" -gt "$MAX_REPOS" ]]; then
    break
  fi

  if [[ "$archived" == "true" && "$INCLUDE_ARCHIVED" -ne 1 ]]; then
    echo "[skip] $ORG/$name (archived)"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$visibility" != "public" && "$ALLOW_PRIVATE" -ne 1 ]]; then
    echo "[skip] $ORG/$name (private)"
    skipped=$((skipped + 1))
    continue
  fi

  cmd=("$REPO_SCRIPT" --config "$CONFIG_FILE" --repo "$ORG/$name")
  [[ "$DRY_RUN" -eq 1 ]] && cmd+=(--dry-run)

  if "${cmd[@]}"; then
    applied=$((applied + 1))
  else
    failed=$((failed + 1))
  fi
done < <(common_repo_list_tsv "$ORG" 200)

echo

echo "Summary: seen=$seen applied=$applied skipped=$skipped failed=$failed dry_run=$DRY_RUN"

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
