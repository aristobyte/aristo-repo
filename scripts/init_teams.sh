#!/usr/bin/env bash
set -euo pipefail

# Initialize org teams from config and grant access to all repos.
# This script manages team metadata + repo permissions only.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/init_teams.sh [options]

Options:
  --config FILE      Team config file (default: ./config/teams.config.json)
  --org ORG          Override org from config
  --dry-run          Print actions without writes
  --max-repos N      Limit repos processed per team
  --include-archived Include archived repos (default: skip archived)
  -h, --help         Show help
USAGE
}

CONFIG_FILE="./config/teams.config.json"
ORG_OVERRIDE=""
DRY_RUN=0
MAX_REPOS=""
INCLUDE_ARCHIVED=0

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
    --max-repos)
      shift
      [[ $# -gt 0 ]] || { echo "--max-repos requires a value" >&2; exit 1; }
      MAX_REPOS="$1"
      [[ "$MAX_REPOS" =~ ^[0-9]+$ ]] || { echo "--max-repos must be non-negative integer" >&2; exit 1; }
      ;;
    --include-archived)
      INCLUDE_ARCHIVED=1
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

common_check_gh_auth

map_role_to_weight() {
  case "$1" in
    all-admin|admin) echo 5 ;;
    all-maintain|maintain) echo 4 ;;
    all-write|write|all-push|push) echo 3 ;;
    all-triage|triage) echo 2 ;;
    all-read|read|all-pull|pull) echo 1 ;;
    all-none|none) echo 0 ;;
    *) echo -1 ;;
  esac
}

weight_to_permission() {
  case "$1" in
    5) echo "admin" ;;
    4) echo "maintain" ;;
    3) echo "push" ;;
    2) echo "triage" ;;
    1) echo "pull" ;;
    0) echo "pull" ;;
    *) echo "pull" ;;
  esac
}

resolve_effective_permission() {
  local roles_json="$1"
  local max_w=0
  while IFS= read -r role; do
    w="$(map_role_to_weight "$role")"
    if [[ "$w" -lt 0 ]]; then
      echo "Unknown role token in config: $role" >&2
      exit 1
    fi
    if [[ "$w" -gt "$max_w" ]]; then
      max_w="$w"
    fi
  done < <(jq -r '.[]' <<<"$roles_json")

  weight_to_permission "$max_w"
}

privacy_from_visible() {
  if [[ "$1" == "true" ]]; then
    echo "closed"
  else
    echo "secret"
  fi
}

notification_from_flag() {
  case "$1" in
    enabled|enable|on|true) echo "notifications_enabled" ;;
    disabled|disable|off|false) echo "notifications_disabled" ;;
    *) echo "notifications_enabled" ;;
  esac
}

ensure_team() {
  local org="$1"
  local slug="$2"
  local title="$3"
  local desc="$4"
  local privacy="$5"
  local notif="$6"

  if gh api "orgs/$org/teams/$slug" >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] update team $org/$slug"
    else
      gh api -X PATCH "orgs/$org/teams/$slug" \
        -f name="$title" \
        -f description="$desc" \
        -f privacy="$privacy" \
        -f notification_setting="$notif" >/dev/null
      echo "updated team: $org/$slug"
    fi
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] create team $org/$slug"
    else
      gh api -X POST "orgs/$org/teams" \
        -f name="$title" \
        -f description="$desc" \
        -f privacy="$privacy" \
        -f notification_setting="$notif" \
        -f permission="pull" >/dev/null
      echo "created team: $org/$slug"
    fi
  fi
}

grant_repo_permission() {
  local org="$1"
  local team_slug="$2"
  local repo_name="$3"
  local perm="$4"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] grant $perm on $org/$repo_name to team $team_slug"
    return
  fi

  gh api -X PUT "orgs/$org/teams/$team_slug/repos/$org/$repo_name" -f permission="$perm" >/dev/null
}

while IFS= read -r team; do
  slug="$(jq -r '.slug' <<<"$team")"
  title="$(jq -r '.title' <<<"$team")"
  desc="$(jq -r '.description // ""' <<<"$team")"
  image="$(jq -r '.image // ""' <<<"$team")"
  roles_json="$(jq -c '.roles // []' <<<"$team")"
  visible="$(jq -r '.visible // true' <<<"$team")"
  notification="$(jq -r '.notification // "enabled"' <<<"$team")"
  access="$(jq -r '.access // "all-repos"' <<<"$team")"

  [[ -n "$slug" && -n "$title" ]] || { echo "Team entry missing slug/title" >&2; exit 1; }

  effective_perm="$(resolve_effective_permission "$roles_json")"
  privacy="$(privacy_from_visible "$visible")"
  notif="$(notification_from_flag "$notification")"

  echo
  echo "== Team: $slug"
  echo "   effective_repo_permission=$effective_perm (from roles=$(jq -c . <<<"$roles_json"))"

  if [[ -n "$image" ]]; then
    if [[ -f "$image" ]]; then
      echo "   image asset found: $image"
    else
      echo "   image asset missing: $image" >&2
    fi
    echo "   note: GitHub team avatar upload is not available in gh REST flow; set avatar in UI after team creation."
  fi

  ensure_team "$ORG" "$slug" "$title" "$desc" "$privacy" "$notif"

  if [[ "$access" != "all-repos" ]]; then
    echo "   access=$access (skipping repo grants)"
    continue
  fi

  count=0
  while IFS= read -r repo_line; do
    repo_name="${repo_line%%$'\t'*}"
    rest="${repo_line#*$'\t'}"
    repo_archived="${rest%%$'\t'*}"

    if [[ "$repo_archived" == "true" && "$INCLUDE_ARCHIVED" -ne 1 ]]; then
      continue
    fi

    count=$((count + 1))
    if [[ -n "$MAX_REPOS" && "$count" -gt "$MAX_REPOS" ]]; then
      break
    fi

    grant_repo_permission "$ORG" "$slug" "$repo_name" "$effective_perm"
  done < <(common_repo_list_tsv "$ORG" 200 | awk -F '\t' '{print $1 "\t" $3}')

done < <(jq -c '.teams[]' "$CONFIG_FILE")

echo
echo "Done."
