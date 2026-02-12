#!/usr/bin/env bash
set -euo pipefail

# Bulk apply policy across one or more orgs.
#
# Defaults:
# - orgs: aristobyte aristobyte-ui
# - public repos only

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/apply_org_policy.sh [options] [org ...]

Options:
  --allow-private   Include private repos
  --dry-run         Print planned actions without API writes
  --max-repos N     Limit repos per org (for staged rollout)
  -h, --help        Show this help
USAGE
}

ALLOW_PRIVATE=0
DRY_RUN=0
MAX_REPOS=""

orgs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-private)
      ALLOW_PRIVATE=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --max-repos)
      shift
      [[ $# -gt 0 ]] || { echo "--max-repos requires a value" >&2; exit 1; }
      MAX_REPOS="$1"
      [[ "$MAX_REPOS" =~ ^[0-9]+$ ]] || { echo "--max-repos must be a non-negative integer" >&2; exit 1; }
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      orgs+=("$1")
      ;;
  esac
  shift
done

if [[ ${#orgs[@]} -eq 0 ]]; then
  orgs=(aristobyte aristobyte-ui)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONE_REPO_SCRIPT="$SCRIPT_DIR/apply_one_repo_policy.sh"

[[ -x "$ONE_REPO_SCRIPT" ]] || {
  echo "Missing executable script: $ONE_REPO_SCRIPT" >&2
  echo "Run: chmod +x $ONE_REPO_SCRIPT" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || { echo "Missing required command: gh" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Missing required command: jq" >&2; exit 1; }

echo "Checking GitHub auth..."
gh auth status >/dev/null

total_seen=0
total_applied=0
total_failed=0
total_skipped=0

for org in "${orgs[@]}"; do
  echo
  echo "=== Org: $org ==="

  repo_list_json="$(gh repo list "$org" --limit 200 --json name,visibility,isArchived)"
  repo_count="$(jq 'length' <<<"$repo_list_json")"
  echo "Found $repo_count repos"

  org_seen=0
  org_applied=0
  org_failed=0
  org_skipped=0

  while IFS= read -r line; do
    repo_name="${line%%$'\t'*}"
    rest="${line#*$'\t'}"
    repo_visibility="${rest%%$'\t'*}"
    repo_archived="${rest##*$'\t'}"

    ((org_seen += 1))

    if [[ -n "$MAX_REPOS" && "$org_seen" -gt "$MAX_REPOS" ]]; then
      break
    fi

    if [[ "$repo_archived" == "true" ]]; then
      echo "[skip] $org/$repo_name (archived)"
      ((org_skipped += 1))
      continue
    fi

    if [[ "$repo_visibility" != "public" && "$ALLOW_PRIVATE" -ne 1 ]]; then
      echo "[skip] $org/$repo_name (private)"
      ((org_skipped += 1))
      continue
    fi

    cmd=("$ONE_REPO_SCRIPT" "$org" "$repo_name" "--repo-visibility" "$repo_visibility" "--repo-archived" "$repo_archived")
    [[ "$ALLOW_PRIVATE" -eq 1 ]] && cmd+=("--allow-private")
    [[ "$DRY_RUN" -eq 1 ]] && cmd+=("--dry-run")

    if "${cmd[@]}"; then
      ((org_applied += 1))
    else
      echo "[error] Failed: $org/$repo_name" >&2
      ((org_failed += 1))
    fi
  done < <(jq -r '.[] | [.name, .visibility, (.isArchived|tostring)] | @tsv' <<<"$repo_list_json")

  total_seen=$((total_seen + org_seen))
  total_applied=$((total_applied + org_applied))
  total_failed=$((total_failed + org_failed))
  total_skipped=$((total_skipped + org_skipped))

  echo "Org summary: seen=$org_seen applied=$org_applied skipped=$org_skipped failed=$org_failed"
done

echo
echo "=== Overall summary ==="
echo "seen=$total_seen applied=$total_applied skipped=$total_skipped failed=$total_failed"

if [[ "$total_failed" -gt 0 ]]; then
  exit 1
fi
