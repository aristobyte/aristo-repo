#!/usr/bin/env bash
set -euo pipefail

# Create/update repository environments across all repos in one org.
# Separate from rulesets, teams, and actions scripts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/update_environments_org.sh [options]

Options:
  --config FILE       Config path (default: ./config/environments.config.json)
  --org ORG           Override org from config
  --dry-run           Print planned actions without writes
  --allow-private     Include private repos for this run
  --include-archived  Include archived repos for this run
  --max-repos N       Limit repos processed
  -h, --help          Show help
USAGE
}

CONFIG_FILE="./config/environments.config.json"
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

mapfile_envs() {
  jq -c '.environments[]' "$CONFIG_FILE"
}

common_check_gh_auth

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

  repo_ok=1
  while IFS= read -r env; do
    env_name="$(jq -r '.name' <<<"$env")"
    wait_timer="$(jq -r '.wait_timer // 0' <<<"$env")"
    prevent_self_review="$(jq -r '.prevent_self_review // false' <<<"$env")"

    [[ -n "$env_name" ]] || { echo "[error] environment name missing" >&2; repo_ok=0; continue; }

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] upsert environment '$env_name' (wait_timer=$wait_timer prevent_self_review=$prevent_self_review)"
      continue
    fi

    tmp_env="$(mktemp -t gh-env-org.XXXXXX)"
    jq -n --argjson wait "$wait_timer" --argjson self "$prevent_self_review" \
      '{wait_timer:$wait, prevent_self_review:$self}' > "$tmp_env"

    if ! gh api -X PUT "repos/$ORG/$repo_name/environments/$env_name" \
      --input "$tmp_env" >/dev/null; then
      echo "[error] failed environment '$env_name'" >&2
      rm -f "$tmp_env"
      repo_ok=0
      continue
    fi

    rm -f "$tmp_env"
    echo "upserted environment: $env_name"
  done < <(mapfile_envs)

  if [[ "$repo_ok" -eq 1 ]]; then
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
