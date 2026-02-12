#!/usr/bin/env bash
set -euo pipefail

# Rulesets-only updater for all repos in one org.
# Does NOT patch repository settings and does NOT create repos.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/update_rulesets_org.sh --org ORG [options]

Options:
  --config FILE            Config path (default: ./config/management.json)
  --allow-private          Include private repos (default: public only)
  --max-repos N            Limit repos processed
  --dry-run                Print actions without API writes
  --bypass-team-slug S     Team slug for bypass placeholder (default: aristo-bypass)
  --reviewer-team-slug S   Team slug for reviewer placeholder (default: aristobyte-approvers)
  -h, --help               Show help
USAGE
}

ORG=""
CONFIG_FILE="./config/management.json"
ALLOW_PRIVATE=0
MAX_REPOS=""
DRY_RUN=0
BYPASS_TEAM_SLUG="aristo-bypass"
REVIEWER_TEAM_SLUG="aristobyte-approvers"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      shift
      [[ $# -gt 0 ]] || { echo "--org requires a value" >&2; exit 1; }
      ORG="$1"
      ;;
    --config)
      shift
      [[ $# -gt 0 ]] || { echo "--config requires a value" >&2; exit 1; }
      CONFIG_FILE="$1"
      ;;
    --allow-private)
      ALLOW_PRIVATE=1
      ;;
    --max-repos)
      shift
      [[ $# -gt 0 ]] || { echo "--max-repos requires a value" >&2; exit 1; }
      MAX_REPOS="$1"
      [[ "$MAX_REPOS" =~ ^[0-9]+$ ]] || { echo "--max-repos must be a non-negative integer" >&2; exit 1; }
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --bypass-team-slug)
      shift
      [[ $# -gt 0 ]] || { echo "--bypass-team-slug requires a value" >&2; exit 1; }
      BYPASS_TEAM_SLUG="$1"
      ;;
    --reviewer-team-slug)
      shift
      [[ $# -gt 0 ]] || { echo "--reviewer-team-slug requires a value" >&2; exit 1; }
      REVIEWER_TEAM_SLUG="$1"
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

[[ -n "$ORG" ]] || { echo "--org is required" >&2; usage; exit 1; }

common_require_gh_jq

[[ -f "$CONFIG_FILE" ]] || { echo "Missing config file: $CONFIG_FILE" >&2; exit 1; }

root_dir="$(cd "$SCRIPT_DIR/.." && pwd)"
policy_dir_cfg="$(jq -r '.policy.policy_dir // "./policy"' "$CONFIG_FILE")"
if [[ "$policy_dir_cfg" = /* ]]; then
  policy_dir="$policy_dir_cfg"
else
  policy_dir="$root_dir/${policy_dir_cfg#./}"
fi

ruleset_files=()
if jq -e '.policy.ruleset_files // [] | type == "array" and length > 0' "$CONFIG_FILE" >/dev/null; then
  while IFS= read -r entry; do
    if [[ "$entry" = /* ]]; then
      rf="$entry"
    else
      rf="$policy_dir/$entry"
    fi
    [[ -f "$rf" ]] || { echo "Missing ruleset file: $rf" >&2; exit 1; }
    ruleset_files+=("$rf")
  done < <(jq -r '.policy.ruleset_files[]' "$CONFIG_FILE")
else
  single="$(jq -r '.policy.ruleset_file // "default-branch-ruleset.json"' "$CONFIG_FILE")"
  if [[ "$single" = /* ]]; then
    rf="$single"
  else
    rf="$policy_dir/$single"
  fi
  [[ -f "$rf" ]] || { echo "Missing ruleset file: $rf" >&2; exit 1; }
  ruleset_files+=("$rf")
fi

common_check_gh_auth

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
  out="$(mktemp /tmp/gh-ruleset-resolved.XXXXXX)"
  out="${out}.json"
  mv "${out%.json}" "$out"
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

temp_files=()
cleanup() {
  if [[ ${#temp_files[@]} -gt 0 ]]; then
    rm -f "${temp_files[@]}" "${temp_files[@]/%/.tmp}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

seen=0
skipped=0
applied=0
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

  if [[ "$repo_archived" == "true" ]]; then
    echo "[skip] $ORG/$repo_name (archived)"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$repo_visibility" != "public" && "$ALLOW_PRIVATE" -ne 1 ]]; then
    echo "[skip] $ORG/$repo_name (private)"
    skipped=$((skipped + 1))
    continue
  fi

  echo
  echo "==> $ORG/$repo_name"

  repo_ok=1
  for rf in "${ruleset_files[@]}"; do
    resolved_rf="$(resolve_ruleset_template "$rf" "$ORG")"
    if [[ -z "$resolved_rf" || ! -f "$resolved_rf" ]]; then
      echo "[error] failed to resolve ruleset template for $rf" >&2
      repo_ok=0
      continue
    fi
    rn="$(ruleset_name_from_file "$resolved_rf")"
    [[ -n "$rn" ]] || { echo "[error] ruleset name missing in $rf" >&2; repo_ok=0; continue; }

    existing_id="$(gh api "repos/$ORG/$repo_name/rulesets" --jq ".[] | select(.name == \"$rn\") | .id" | head -n1 || true)"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      if [[ -n "$existing_id" ]]; then
        echo "[dry-run] update ruleset '$rn' id=$existing_id from $rf"
      else
        echo "[dry-run] create ruleset '$rn' from $rf"
      fi
      continue
    fi

    if [[ -n "$existing_id" ]]; then
      if gh api -X PUT "repos/$ORG/$repo_name/rulesets/$existing_id" --input "$resolved_rf" >/dev/null; then
        echo "updated: $rn"
      else
        echo "[error] update failed: $rn" >&2
        repo_ok=0
      fi
    else
      if gh api -X POST "repos/$ORG/$repo_name/rulesets" --input "$resolved_rf" >/dev/null; then
        echo "created: $rn"
      else
        echo "[error] create failed: $rn" >&2
        repo_ok=0
      fi
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
