#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/update_actions_policy_repo.sh --repo ORG/REPO [--config FILE] [--dry-run]
USAGE
}

REPO_FULL=""
CONFIG_FILE="./config/actions.config.json"
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

mode="$(jq -r '.policy.allowed_actions_mode // "selected"' "$CONFIG_FILE")"
allow_github_owned="$(jq -r '.policy.allow_github_owned // true' "$CONFIG_FILE")"
allow_verified_creators="$(jq -r '.policy.allow_verified_creators // false' "$CONFIG_FILE")"

patterns=()
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  patterns+=("${p//\{ORG\}/$ORG}")
done < <(jq -r '.policy.patterns_allowed[]?' "$CONFIG_FILE")

case "$mode" in
  all|local_only|selected) ;;
  *)
    echo "Unsupported allowed_actions_mode: $mode" >&2
    exit 1
    ;;
esac

if [[ "$mode" == "selected" && ${#patterns[@]} -eq 0 ]]; then
  echo "selected mode requires at least one pattern" >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] set actions policy on $REPO_FULL: mode=$mode"
  if [[ "$mode" == "selected" ]]; then
    echo "[dry-run] selected-actions github_owned_allowed=$allow_github_owned verified_allowed=$allow_verified_creators"
    for p in "${patterns[@]}"; do
      echo "[dry-run]   pattern: $p"
    done
  fi
  exit 0
fi

tmp_actions="$(mktemp -t gh-actions-perm.XXXXXX)"
jq -n --arg mode "$mode" '{enabled:true, allowed_actions:$mode}' > "$tmp_actions"
gh api -X PUT "repos/$ORG/$REPO/actions/permissions" --input "$tmp_actions" >/dev/null
rm -f "$tmp_actions"

if [[ "$mode" == "selected" ]]; then
  tmp_selected="$(mktemp -t gh-actions-selected.XXXXXX)"
  printf '%s\n' "${patterns[@]}" | jq -Rsc \
    --argjson gh_owned "$allow_github_owned" \
    --argjson verified "$allow_verified_creators" \
    '{github_owned_allowed:$gh_owned, verified_allowed:$verified, patterns_allowed:(split("\n")[:-1])}' > "$tmp_selected"
  gh api -X PUT "repos/$ORG/$REPO/actions/permissions/selected-actions" --input "$tmp_selected" >/dev/null
  rm -f "$tmp_selected"
fi

echo "updated actions policy: $REPO_FULL"
