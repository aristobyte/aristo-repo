#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/update_security_policy_repo.sh --repo ORG/REPO [--config FILE] [--dry-run]
USAGE
}

REPO_FULL=""
CONFIG_FILE="./config/security.config.json"
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

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] apply security policy on $REPO_FULL"
  exit 0
fi

vulnerability_alerts="$(jq -r '.policy.vulnerability_alerts // true' "$CONFIG_FILE")"
automated_security_fixes="$(jq -r '.policy.automated_security_fixes // true' "$CONFIG_FILE")"
private_vulnerability_reporting="$(jq -r '.policy.private_vulnerability_reporting // true' "$CONFIG_FILE")"

if [[ "$vulnerability_alerts" == "true" ]]; then
  gh api -X PUT "repos/$ORG/$REPO/vulnerability-alerts" >/dev/null || true
else
  gh api -X DELETE "repos/$ORG/$REPO/vulnerability-alerts" >/dev/null || true
fi

if [[ "$automated_security_fixes" == "true" ]]; then
  gh api -X PUT "repos/$ORG/$REPO/automated-security-fixes" >/dev/null || true
else
  gh api -X DELETE "repos/$ORG/$REPO/automated-security-fixes" >/dev/null || true
fi

if [[ "$private_vulnerability_reporting" == "true" ]]; then
  gh api -X PUT "repos/$ORG/$REPO/private-vulnerability-reporting" >/dev/null || true
else
  gh api -X DELETE "repos/$ORG/$REPO/private-vulnerability-reporting" >/dev/null || true
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

for key in "${security_keys[@]}"; do
  status="$(jq -r --arg k "$key" '.policy.security_and_analysis[$k] // empty' "$CONFIG_FILE")"
  [[ -z "$status" ]] && continue
  [[ "$status" == "enabled" || "$status" == "disabled" ]] || {
    echo "Invalid value for policy.security_and_analysis.$key: $status" >&2
    exit 1
  }
  tmp="$(mktemp /tmp/gh-sec-repo.XXXXXX)"
  jq -n --arg key "$key" --arg status "$status" '{security_and_analysis:{($key):{status:$status}}}' > "$tmp"
  if ! err="$(gh api -X PATCH "repos/$ORG/$REPO" --input "$tmp" >/dev/null 2>&1)"; then
    if [[ "$err" != *"Advanced security is always available for public repos."* ]]; then
      echo "[warn] security_and_analysis.$key update failed: $err" >&2
    fi
  fi
  rm -f "$tmp"
done

echo "updated security policy: $REPO_FULL"
