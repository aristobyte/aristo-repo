#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/update_rulesets_repo.sh --repo ORG/REPO [--config FILE] [--dry-run]
USAGE
}

REPO_FULL=""
CONFIG_FILE="./config/management.json"
DRY_RUN=0
BYPASS_TEAM_SLUG="aristo-bypass"
REVIEWER_TEAM_SLUG="aristobyte-approvers"

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
    --bypass-team-slug)
      shift
      [[ $# -gt 0 ]] || { echo "--bypass-team-slug requires a value" >&2; exit 1; }
      BYPASS_TEAM_SLUG="${1:-}"
      ;;
    --reviewer-team-slug)
      shift
      [[ $# -gt 0 ]] || { echo "--reviewer-team-slug requires a value" >&2; exit 1; }
      REVIEWER_TEAM_SLUG="${1:-}"
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
[[ -f "$CONFIG_FILE" ]] || { echo "Missing config: $CONFIG_FILE" >&2; exit 1; }
jq . "$CONFIG_FILE" >/dev/null

version="$(jq -r '.version // 0' "$CONFIG_FILE")"
[[ "$version" == "1" ]] || { echo "Unsupported config version: $version" >&2; exit 1; }

root_dir="$(cd "$SCRIPT_DIR/.." && pwd)"
policy_dir_cfg="$(jq -r '.policy.policy_dir // "./policy"' "$CONFIG_FILE")"
if [[ "$policy_dir_cfg" = /* ]]; then
  policy_dir="$policy_dir_cfg"
else
  policy_dir="$root_dir/${policy_dir_cfg#./}"
fi
ruleset_files=()
if jq -e '.policy.ruleset_files // [] | type=="array" and length>0' "$CONFIG_FILE" >/dev/null; then
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" = /* ]]; then
      ruleset_files+=("$entry")
    else
      ruleset_files+=("$policy_dir/$entry")
    fi
  done < <(jq -r '.policy.ruleset_files[]' "$CONFIG_FILE")
else
  one="$(jq -r '.policy.ruleset_file // "default-branch-ruleset.json"' "$CONFIG_FILE")"
  if [[ "$one" = /* ]]; then
    ruleset_files+=("$one")
  else
    ruleset_files+=("$policy_dir/$one")
  fi
fi

for rf in "${ruleset_files[@]}"; do
  [[ -f "$rf" ]] || { echo "Missing ruleset file: $rf" >&2; exit 1; }
done

common_check_gh_auth

tmp_files=()
cleanup() {
  if [[ ${#tmp_files[@]} -gt 0 ]]; then
    rm -f "${tmp_files[@]}" "${tmp_files[@]/%/.a}" "${tmp_files[@]/%/.b}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

team_id_by_slug() {
  gh api "orgs/$1/teams/$2" --jq '.id'
}

resolve_template() {
  local src="$1"
  if ! grep -Eq "__BYPASS_TEAM_ID__|__REQUIRED_REVIEWER_TEAM_ID__" "$src"; then
    echo "$src"
    return
  fi

  local tmp
  tmp="$(mktemp -t gh-ruleset-repo.XXXXXX)"
  tmp_files+=("$tmp")
  cp "$src" "$tmp"

  if grep -Eq "__BYPASS_TEAM_ID__" "$tmp"; then
    local bypass_id
    bypass_id="$(team_id_by_slug "$ORG" "$BYPASS_TEAM_SLUG")"
    jq --argjson id "$bypass_id" '.bypass_actors |= map(if .actor_id=="__BYPASS_TEAM_ID__" then .actor_id=$id else . end)' "$tmp" > "${tmp}.a"
    mv "${tmp}.a" "$tmp"
  fi

  if grep -Eq "__REQUIRED_REVIEWER_TEAM_ID__" "$tmp"; then
    local reviewer_id
    reviewer_id="$(team_id_by_slug "$ORG" "$REVIEWER_TEAM_SLUG")"
    jq --argjson id "$reviewer_id" '(.rules[]? | select(.type=="pull_request") | .parameters.required_reviewers[]? | .reviewer) |= (if .id=="__REQUIRED_REVIEWER_TEAM_ID__" then .id=$id else . end)' "$tmp" > "${tmp}.b"
    mv "${tmp}.b" "$tmp"
  fi

  echo "$tmp"
}

for rf in "${ruleset_files[@]}"; do
  resolved="$(resolve_template "$rf")"
  ruleset_name="$(jq -r '.name // empty' "$resolved")"
  [[ -n "$ruleset_name" ]] || { echo "Missing ruleset name in $rf" >&2; exit 1; }

  existing_id="$(gh api "repos/$ORG/$REPO/rulesets" --jq ".[] | select(.name == \"$ruleset_name\") | .id" | head -n1 || true)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ -n "$existing_id" ]]; then
      echo "[dry-run] update ruleset: $ruleset_name"
    else
      echo "[dry-run] create ruleset: $ruleset_name"
    fi
    continue
  fi

  if [[ -n "$existing_id" ]]; then
    gh api -X PUT "repos/$ORG/$REPO/rulesets/$existing_id" --input "$resolved" >/dev/null
    echo "updated: $ruleset_name"
  else
    gh api -X POST "repos/$ORG/$REPO/rulesets" --input "$resolved" >/dev/null
    echo "created: $ruleset_name"
  fi
done
