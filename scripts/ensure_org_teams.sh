#!/usr/bin/env bash
set -euo pipefail

# Ensure org teams for repo governance exist.
# - Aristo-Approvers: PR approval team
# - Aristo-Bypass: single-user bypass team for ruleset bypass needs

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/ensure_org_teams.sh <org> [options]

Options:
  --owner-user USER      Add this user to Aristo-Bypass (default: aristobyte-team)
  --dry-run              Print planned actions only
  -h, --help             Show help
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ORG="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

[[ -n "$ORG" ]] || { usage; exit 1; }

OWNER_USER="aristobyte-team"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner-user)
      shift
      [[ $# -gt 0 ]] || { echo "--owner-user requires a value" >&2; exit 1; }
      OWNER_USER="$1"
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

command -v gh >/dev/null 2>&1 || { echo "Missing required command: gh" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Missing required command: jq" >&2; exit 1; }

echo "Checking GitHub auth..."
gh auth status >/dev/null

ensure_team() {
  local org="$1"
  local name="$2"
  local slug="$3"
  local desc="$4"

  if gh api "orgs/$org/teams/$slug" >/dev/null 2>&1; then
    echo "Team exists: $org/$slug"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] create team: $org/$name ($slug)"
    return
  fi

  gh api -X POST "orgs/$org/teams" \
    -f name="$name" \
    -f description="$desc" \
    -f privacy="closed" \
    -f permission="pull" >/dev/null

  echo "Team created: $org/$slug"
}

ensure_member() {
  local org="$1"
  local slug="$2"
  local user="$3"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] ensure member: $user in $org/$slug"
    return
  fi

  gh api -X PUT "orgs/$org/teams/$slug/memberships/$user" \
    -f role="member" >/dev/null

  echo "Member ensured: $user -> $org/$slug"
}

ensure_team "$ORG" "Aristo-Approvers" "aristo-approvers" "Allowed reviewers for protected branch PR approvals"
ensure_team "$ORG" "Aristo-Bypass" "aristo-bypass" "Single-user bypass team for emergency ruleset bypass"
ensure_member "$ORG" "aristo-bypass" "$OWNER_USER"

echo
for slug in aristo-approvers aristo-bypass; do
  if gh api "orgs/$ORG/teams/$slug" >/dev/null 2>&1; then
    gh api "orgs/$ORG/teams/$slug" --jq '"team=" + .slug + " id=" + (.id|tostring)'
  fi
done
