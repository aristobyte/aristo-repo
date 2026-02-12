#!/usr/bin/env bash
set -euo pipefail

# Apply GitHub Actions permissions policy across repos in one org.
# This script is separate from rulesets and teams.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/update_actions_policy_org.sh [options]

Options:
  --config FILE       Config path (default: ./config/actions.config.json)
  --org ORG           Override org from config
  --dry-run           Print planned actions without writes
  --allow-private     Include private repos for this run
  --include-archived  Include archived repos for this run
  --max-repos N       Limit repos processed
  -h, --help          Show help
USAGE
}

CONFIG_FILE="./config/actions.config.json"
ORG_OVERRIDE=""
DRY_RUN=0
ALLOW_PRIVATE_OVERRIDE=""
INCLUDE_ARCHIVED_OVERRIDE=""
MAX_REPOS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      shift
      [[ $# -gt 0 ]] || { echo "--config requires a value" >&2; exit 1; }
      CONFIG_FILE="$1"
      ;;
    --org)
      shift
      [[ $# -gt 0 ]] || { echo "--org requires a value" >&2; exit 1; }
      ORG_OVERRIDE="$1"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --allow-private)
      ALLOW_PRIVATE_OVERRIDE="true"
      ;;
    --include-archived)
      INCLUDE_ARCHIVED_OVERRIDE="true"
      ;;
    --max-repos)
      shift
      [[ $# -gt 0 ]] || { echo "--max-repos requires a value" >&2; exit 1; }
      MAX_REPOS="$1"
      [[ "$MAX_REPOS" =~ ^[0-9]+$ ]] || { echo "--max-repos must be non-negative integer" >&2; exit 1; }
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

common_require_gh_jq

[[ -f "$CONFIG_FILE" ]] || { echo "Missing config file: $CONFIG_FILE" >&2; exit 1; }
jq . "$CONFIG_FILE" >/dev/null

version="$(jq -r '.version // 0' "$CONFIG_FILE")"
[[ "$version" == "1" ]] || { echo "Unsupported config version: $version" >&2; exit 1; }

ORG="$(jq -r '.org // empty' "$CONFIG_FILE")"
[[ -n "$ORG" ]] || { echo "Missing .org in config" >&2; exit 1; }
[[ -n "$ORG_OVERRIDE" ]] && ORG="$ORG_OVERRIDE"

include_private_cfg="$(jq -r '.execution.include_private // true' "$CONFIG_FILE")"
include_archived_cfg="$(jq -r '.execution.include_archived // false' "$CONFIG_FILE")"

if [[ -n "$ALLOW_PRIVATE_OVERRIDE" ]]; then
  include_private="$ALLOW_PRIVATE_OVERRIDE"
else
  include_private="$include_private_cfg"
fi

if [[ -n "$INCLUDE_ARCHIVED_OVERRIDE" ]]; then
  include_archived="$INCLUDE_ARCHIVED_OVERRIDE"
else
  include_archived="$include_archived_cfg"
fi

enabled="$(jq -r '.policy.enabled // true' "$CONFIG_FILE")"
[[ "$enabled" == "true" ]] || { echo "Policy is disabled in config"; exit 0; }

mode="$(jq -r '.policy.allowed_actions_mode // "selected"' "$CONFIG_FILE")"
allow_github_owned="$(jq -r '.policy.allow_github_owned // true' "$CONFIG_FILE")"
allow_verified_creators="$(jq -r '.policy.allow_verified_creators // false' "$CONFIG_FILE")"

case "$mode" in
  all|local_only|selected) ;;
  *) echo "Unsupported allowed_actions_mode: $mode" >&2; exit 1 ;;
esac

common_check_gh_auth

action_mode_payload="$mode"
if [[ "$mode" == "local_only" ]]; then
  action_mode_payload="local_only"
elif [[ "$mode" == "all" ]]; then
  action_mode_payload="all"
else
  action_mode_payload="selected"
fi

mapfile_patterns() {
  local cfg="$1"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    p="${p//\{ORG\}/$ORG}"
    echo "$p"
  done < <(jq -r '.policy.patterns_allowed[]?' "$cfg")
}

patterns=()
while IFS= read -r line; do
  [[ -n "$line" ]] && patterns+=("$line")
done < <(mapfile_patterns "$CONFIG_FILE")

if [[ "$action_mode_payload" == "selected" && ${#patterns[@]} -eq 0 ]]; then
  echo "selected mode requires at least one pattern in policy.patterns_allowed" >&2
  exit 1
fi

seen=0
applied=0
skipped=0
failed=0

while IFS= read -r line; do
  repo_name="${line%%$'\t'*}"
  rest="${line#*$'\t'}"
  repo_visibility="${rest%%$'\t'*}"
  repo_archived="${rest##*$'\t'}"

  seen=$((seen + 1))
  if [[ -n "$MAX_REPOS" && "$seen" -gt "$MAX_REPOS" ]]; then
    break
  fi

  if [[ "$repo_archived" == "true" && "$include_archived" != "true" ]]; then
    echo "[skip] $ORG/$repo_name (archived)"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$repo_visibility" != "public" && "$include_private" != "true" ]]; then
    echo "[skip] $ORG/$repo_name (private)"
    skipped=$((skipped + 1))
    continue
  fi

  echo
  echo "==> $ORG/$repo_name"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] set actions permissions: enabled=true allowed_actions=$action_mode_payload"
    if [[ "$action_mode_payload" == "selected" ]]; then
      echo "[dry-run] set selected actions: github_owned_allowed=$allow_github_owned verified_allowed=$allow_verified_creators"
      for p in "${patterns[@]}"; do
        echo "[dry-run]   pattern: $p"
      done
    fi
    applied=$((applied + 1))
    continue
  fi

  tmp_actions="$(mktemp -t gh-actions-org-perm.XXXXXX)"
  jq -n --arg mode "$action_mode_payload" '{enabled:true, allowed_actions:$mode}' > "$tmp_actions"
  if ! gh api -X PUT "repos/$ORG/$repo_name/actions/permissions" \
      --input "$tmp_actions" >/dev/null; then
    echo "[error] failed setting actions permissions on $ORG/$repo_name" >&2
    rm -f "$tmp_actions"
    failed=$((failed + 1))
    continue
  fi
  rm -f "$tmp_actions"

  if [[ "$action_mode_payload" == "selected" ]]; then
    tmp_selected="$(mktemp -t gh-actions-org-selected.XXXXXX)"
    printf '%s\n' "${patterns[@]}" | jq -Rsc \
      --argjson gh_owned "$allow_github_owned" \
      --argjson verified "$allow_verified_creators" \
      '{github_owned_allowed:$gh_owned, verified_allowed:$verified, patterns_allowed:(split("\n")[:-1])}' > "$tmp_selected"
    if ! gh api -X PUT "repos/$ORG/$repo_name/actions/permissions/selected-actions" --input "$tmp_selected" >/dev/null; then
      echo "[error] failed setting selected actions on $ORG/$repo_name" >&2
      rm -f "$tmp_selected"
      failed=$((failed + 1))
      continue
    fi
    rm -f "$tmp_selected"
  fi

  echo "updated actions policy"
  applied=$((applied + 1))
done < <(common_repo_list_tsv "$ORG" 200)

echo
echo "Summary: seen=$seen applied=$applied skipped=$skipped failed=$failed dry_run=$DRY_RUN"

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
