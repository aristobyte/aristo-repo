#!/usr/bin/env bash
set -euo pipefail

# Remove managed teams listed in teams.config.json from an org.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/remove_teams_org.sh --org ORG [--config FILE] [--dry-run]
USAGE
}

ORG=""
CONFIG_FILE="./config/teams.config.json"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      shift
      [[ $# -gt 0 ]] || { echo "--org requires a value" >&2; exit 1; }
      ORG="$1"
      ;;
    --config)
      shift
      [[ $# -gt 0 ]] || { echo "--config requires a value" >&2; exit 1; }
      CONFIG_FILE="$1"
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

common_require_gh_jq
[[ -f "$CONFIG_FILE" ]] || { echo "Missing config: $CONFIG_FILE" >&2; exit 1; }

jq . "$CONFIG_FILE" >/dev/null

common_check_gh_auth

while IFS= read -r slug; do
  [[ -n "$slug" ]] || continue

  if ! gh api "orgs/$ORG/teams/$slug" >/dev/null 2>&1; then
    echo "[skip] team not found: $ORG/$slug"
    continue
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] delete team: $ORG/$slug"
  else
    gh api -X DELETE "orgs/$ORG/teams/$slug" >/dev/null
    echo "deleted team: $ORG/$slug"
  fi
done < <(jq -r '.teams[]?.slug' "$CONFIG_FILE")

echo "Done"
