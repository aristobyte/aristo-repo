#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/update_environments_repo.sh --repo ORG/REPO [--config FILE] [--dry-run]
USAGE
}

REPO_FULL=""
CONFIG_FILE="./config/environments.config.json"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      shift
      [[ $# -gt 0 ]] || { echo "--repo requires a value" >&2; exit 1; }
      REPO_FULL="${1:-}"
      ;;
    --config)
      shift
      [[ $# -gt 0 ]] || { echo "--config requires a value" >&2; exit 1; }
      CONFIG_FILE="${1:-}"
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

[[ "$REPO_FULL" == */* ]] || { echo "--repo must be ORG/REPO" >&2; usage; exit 1; }
IFS='/' read -r ORG REPO <<< "$REPO_FULL"

common_require_gh_jq
common_check_gh_auth
[[ -f "$CONFIG_FILE" ]] || { echo "Missing config: $CONFIG_FILE" >&2; exit 1; }
jq . "$CONFIG_FILE" >/dev/null

version="$(jq -r '.version // 0' "$CONFIG_FILE")"
[[ "$version" == "1" ]] || { echo "Unsupported config version: $version" >&2; exit 1; }

while IFS= read -r env; do
  name="$(jq -r '.name' <<<"$env")"
  wait_timer="$(jq -r '.wait_timer // 0' <<<"$env")"
  prevent_self_review="$(jq -r '.prevent_self_review // false' <<<"$env")"
  [[ -n "$name" ]] || { echo "Environment entry has empty name" >&2; exit 1; }

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] upsert env '$name' on $REPO_FULL (wait_timer=$wait_timer prevent_self_review=$prevent_self_review)"
    continue
  fi

  tmp_env="$(mktemp -t gh-env-repo.XXXXXX)"
  jq -n --argjson wait "$wait_timer" --argjson self "$prevent_self_review" \
    '{wait_timer:$wait, prevent_self_review:$self}' > "$tmp_env"
  gh api -X PUT "repos/$ORG/$REPO/environments/$name" --input "$tmp_env" >/dev/null
  rm -f "$tmp_env"
  echo "upserted env: $name"
done < <(jq -c '.environments[]' "$CONFIG_FILE")
