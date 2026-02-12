#!/usr/bin/env bash
set -euo pipefail

# Apply repo settings + one or more rulesets to a single repository.

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/apply_one_repo_policy.sh <org> <repo> [options]

Options:
  --allow-private          Apply policy to private repos too (default: skip private)
  --repo-visibility VALUE  Pre-fetched visibility (public/private/internal) to skip repo lookup
  --repo-archived BOOL     Pre-fetched archived flag (true/false) to skip repo lookup
  --dry-run                Print planned actions without API writes
  -h, --help               Show this help
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ORG="${1:-}"
REPO="${2:-}"
shift $(( $# >= 2 ? 2 : $# ))

if [[ -z "$ORG" || -z "$REPO" ]]; then
  usage
  exit 1
fi

ALLOW_PRIVATE=0
DRY_RUN=0
REPO_VISIBILITY=""
REPO_ARCHIVED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-private)
      ALLOW_PRIVATE=1
      ;;
    --repo-visibility)
      shift
      [[ $# -gt 0 ]] || { echo "--repo-visibility requires a value" >&2; exit 1; }
      REPO_VISIBILITY="$1"
      ;;
    --repo-archived)
      shift
      [[ $# -gt 0 ]] || { echo "--repo-archived requires a value" >&2; exit 1; }
      REPO_ARCHIVED="$1"
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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd gh
require_cmd jq

POLICY_DIR="${POLICY_DIR:-./policy}"
REPO_SETTINGS_FILE="${REPO_SETTINGS_FILE:-$POLICY_DIR/repo-settings.json}"
RULESET_FILE="${RULESET_FILE:-$POLICY_DIR/default-branch-ruleset.json}"
RULESET_FILES_JSON="${RULESET_FILES_JSON:-}"
RULESET_NAME="${RULESET_NAME:-}"
BYPASS_TEAM_SLUG="${BYPASS_TEAM_SLUG:-aristo-bypass}"
REVIEWER_TEAM_SLUG="${REVIEWER_TEAM_SLUG:-aristobyte-approvers}"

[[ -f "$REPO_SETTINGS_FILE" ]] || { echo "Missing file: $REPO_SETTINGS_FILE" >&2; exit 1; }

ruleset_files=()
if [[ -n "$RULESET_FILES_JSON" ]]; then
  while IFS= read -r rf; do
    [[ -n "$rf" ]] && ruleset_files+=("$rf")
  done < <(jq -r '.[]' <<<"$RULESET_FILES_JSON")
else
  ruleset_files=("$RULESET_FILE")
fi

[[ ${#ruleset_files[@]} -gt 0 ]] || { echo "No ruleset files configured" >&2; exit 1; }
for rf in "${ruleset_files[@]}"; do
  [[ -f "$rf" ]] || { echo "Missing ruleset file: $rf" >&2; exit 1; }
done

echo "Checking GitHub auth..."
gh auth status >/dev/null

if [[ -n "$REPO_VISIBILITY" && -n "$REPO_ARCHIVED" ]]; then
  visibility="$REPO_VISIBILITY"
  archived="$REPO_ARCHIVED"
else
  repo_json="$(gh api "repos/$ORG/$REPO" --jq '{visibility, archived}')"
  visibility="$(jq -r '.visibility' <<<"$repo_json")"
  archived="$(jq -r '.archived' <<<"$repo_json")"
fi

if [[ "$archived" == "true" ]]; then
  echo "Skipping $ORG/$REPO (archived)."
  exit 0
fi

if [[ "$visibility" != "public" && "$ALLOW_PRIVATE" -ne 1 ]]; then
  echo "Skipping $ORG/$REPO (visibility=$visibility, use --allow-private to include)."
  exit 0
fi

echo "Applying policy to $ORG/$REPO (visibility=$visibility)"

temp_files=()
cleanup() {
  if [[ ${#temp_files[@]} -gt 0 ]]; then
    rm -f "${temp_files[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

team_id_by_slug() {
  local org="$1"
  local slug="$2"
  gh api "orgs/$org/teams/$slug" --jq '.id'
}

resolve_ruleset_template() {
  local src="$1"
  local org="$2"

  if ! grep -Eq "__BYPASS_TEAM_ID__|__REQUIRED_REVIEWER_TEAM_ID__" "$src"; then
    echo "$src"
    return
  fi

  local out
  out="$(mktemp -t gh-ruleset-resolved.XXXXXX)"
  temp_files+=("$out")
  cp "$src" "$out"

  if grep -Eq "__BYPASS_TEAM_ID__" "$out"; then
    local bypass_id
    bypass_id="$(team_id_by_slug "$org" "$BYPASS_TEAM_SLUG")"
    jq --argjson id "$bypass_id" '
      .bypass_actors |=
      (map(if .actor_id == "__BYPASS_TEAM_ID__" then .actor_id = $id else . end))
    ' "$out" > "${out}.tmp"
    mv "${out}.tmp" "$out"
  fi

  if grep -Eq "__REQUIRED_REVIEWER_TEAM_ID__" "$out"; then
    local reviewer_id
    reviewer_id="$(team_id_by_slug "$org" "$REVIEWER_TEAM_SLUG")"
    jq --argjson id "$reviewer_id" '
      (.rules[]? | select(.type=="pull_request") | .parameters.required_reviewers[]? | .reviewer) |=
      (if .id == "__REQUIRED_REVIEWER_TEAM_ID__" then .id = $id else . end)
    ' "$out" > "${out}.tmp"
    mv "${out}.tmp" "$out"
  fi

  echo "$out"
}

ruleset_name_from_file() {
  local file="$1"
  jq -r '.name // empty' "$file"
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] gh api -X PATCH repos/$ORG/$REPO --input $REPO_SETTINGS_FILE"
  for rf in "${ruleset_files[@]}"; do
    rn="$(ruleset_name_from_file "$rf")"
    [[ -n "$rn" ]] || { echo "Ruleset file has no name: $rf" >&2; exit 1; }

    if grep -Eq "__BYPASS_TEAM_ID__|__REQUIRED_REVIEWER_TEAM_ID__" "$rf"; then
      echo "[dry-run] ruleset template placeholders in $rf"
      echo "          BYPASS_TEAM_SLUG=$BYPASS_TEAM_SLUG REVIEWER_TEAM_SLUG=$REVIEWER_TEAM_SLUG"
    fi

    echo "[dry-run] gh api repos/$ORG/$REPO/rulesets (lookup by name: $rn)"
    echo "[dry-run] gh api -X PUT repos/$ORG/$REPO/rulesets/<id> --input $rf (if exists)"
    echo "[dry-run] gh api -X POST repos/$ORG/$REPO/rulesets --input $rf (if missing)"
  done
  echo "Dry-run complete for $ORG/$REPO"
  exit 0
fi

gh api -X PATCH "repos/$ORG/$REPO" --input "$REPO_SETTINGS_FILE" >/dev/null

applied=0
for rf in "${ruleset_files[@]}"; do
  resolved_rf="$(resolve_ruleset_template "$rf" "$ORG")"
  [[ -n "$resolved_rf" && -f "$resolved_rf" ]] || { echo "Failed to resolve ruleset file: $rf" >&2; exit 1; }
  rn="$(ruleset_name_from_file "$resolved_rf")"

  if [[ ${#ruleset_files[@]} -eq 1 && -n "$RULESET_NAME" ]]; then
    rn="$RULESET_NAME"
  fi

  [[ -n "$rn" ]] || { echo "Unable to resolve ruleset name from $rf" >&2; exit 1; }

  existing_ruleset_id="$(gh api "repos/$ORG/$REPO/rulesets" --jq ".[] | select(.name == \"$rn\") | .id" | head -n1 || true)"

  if [[ -n "$existing_ruleset_id" ]]; then
    gh api -X PUT "repos/$ORG/$REPO/rulesets/$existing_ruleset_id" --input "$resolved_rf" >/dev/null
    echo "Applied ruleset: updated $rn (id=$existing_ruleset_id)"
  else
    gh api -X POST "repos/$ORG/$REPO/rulesets" --input "$resolved_rf" >/dev/null
    echo "Applied ruleset: created $rn"
  fi

  applied=$((applied + 1))
done

echo "Applied: settings patched, rulesets applied=$applied"

gh api "repos/$ORG/$REPO" \
  --jq '{name,default_branch,visibility,allow_squash_merge,allow_merge_commit,allow_rebase_merge,delete_branch_on_merge,allow_auto_merge}'

gh api "repos/$ORG/$REPO/rulesets" \
  --jq 'map({id,name,target,enforcement})'
