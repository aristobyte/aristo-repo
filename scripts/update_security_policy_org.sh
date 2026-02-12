#!/usr/bin/env bash
set -euo pipefail

# Apply repository security settings across all repos in one org.
# Separate from rulesets/teams/actions/environments scripts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/update_security_policy_org.sh [options]

Options:
  --config FILE       Config path (default: ./config/security.config.json)
  --org ORG           Override org from config
  --dry-run           Print planned actions without writes
  --allow-private     Include private repos for this run
  --include-archived  Include archived repos for this run
  --max-repos N       Limit repos processed
  -h, --help          Show help
USAGE
}

CONFIG_FILE="./config/security.config.json"
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

security_keys=(
  dependency_graph
  dependabot_alerts
  dependabot_security_updates
  secret_scanning
  secret_scanning_push_protection
  secret_scanning_non_provider_patterns
  advanced_security
)

common_check_gh_auth

temp_files=()
cleanup() {
  if [[ ${#temp_files[@]} -gt 0 ]]; then
    rm -f "${temp_files[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

apply_toggle_endpoint() {
  local endpoint="$1"
  local enabled="$2"

  if [[ "$enabled" == "true" ]]; then
    gh api -X PUT "$endpoint" >/dev/null
  else
    gh api -X DELETE "$endpoint" >/dev/null
  fi
}

apply_security_analysis_key() {
  local org="$1"
  local repo="$2"
  local key="$3"
  local status="$4"

  tmp="$(mktemp /tmp/gh-security-key.XXXXXX)"
  temp_files+=("$tmp")
  jq -n --arg key "$key" --arg status "$status" '{security_and_analysis:{($key):{status:$status}}}' > "$tmp"

  local err
  if ! err="$(gh api -X PATCH "repos/$org/$repo" --input "$tmp" >/dev/null 2>&1)"; then
    if [[ "$err" == *"Advanced security is always available for public repos."* ]]; then
      return 0
    fi
    echo "$err" >&2
    return 1
  fi
}

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

  vuln_alerts="$(jq -r '.policy.vulnerability_alerts // true' "$CONFIG_FILE")"
  auto_fixes="$(jq -r '.policy.automated_security_fixes // true' "$CONFIG_FILE")"
  private_vr="$(jq -r '.policy.private_vulnerability_reporting // false' "$CONFIG_FILE")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] vulnerability_alerts=$vuln_alerts automated_security_fixes=$auto_fixes private_vulnerability_reporting=$private_vr"
  else
    if ! apply_toggle_endpoint "repos/$ORG/$repo_name/vulnerability-alerts" "$vuln_alerts"; then
      echo "[warn] vulnerability-alerts endpoint failed (may be unsupported/permission constrained)"
      repo_ok=0
    fi

    if ! apply_toggle_endpoint "repos/$ORG/$repo_name/automated-security-fixes" "$auto_fixes"; then
      echo "[warn] automated-security-fixes endpoint failed (may be unsupported/permission constrained)"
      repo_ok=0
    fi

    if ! apply_toggle_endpoint "repos/$ORG/$repo_name/private-vulnerability-reporting" "$private_vr"; then
      echo "[warn] private-vulnerability-reporting endpoint failed (may be unsupported for this repo type)"
      repo_ok=0
    fi
  fi

  for key in "${security_keys[@]}"; do
    status="$(jq -r --arg k "$key" '.policy.security_and_analysis[$k] // empty' "$CONFIG_FILE")"
    if [[ -z "$status" ]]; then
      continue
    fi

    if [[ "$status" != "enabled" && "$status" != "disabled" ]]; then
      echo "[error] invalid security_and_analysis.$key value: $status" >&2
      repo_ok=0
      continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] security_and_analysis.$key=$status"
      continue
    fi

    if apply_security_analysis_key "$ORG" "$repo_name" "$key" "$status"; then
      echo "updated: security_and_analysis.$key=$status"
    else
      echo "[warn] failed security_and_analysis.$key=$status (unsupported/plan-limited?)"
      repo_ok=0
    fi
  done

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
