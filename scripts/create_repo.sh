#!/usr/bin/env bash
set -euo pipefail

# Create (or detect existing) repo, then optionally apply repository policy.

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/create_repo.sh <org> <repo> [options]

Options:
  --public                 Create public repo (default)
  --private                Create private repo
  --description TEXT       Repo description
  --template OWNER/REPO    Create from template
  --no-apply-policy        Do not run apply_one_repo_policy after create/check
  --allow-private-policy   Allow policy application for private repos
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

VISIBILITY="public"
DESCRIPTION=""
TEMPLATE=""
APPLY_POLICY=1
ALLOW_PRIVATE_POLICY=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public)
      VISIBILITY="public"
      ;;
    --private)
      VISIBILITY="private"
      ;;
    --description)
      shift
      [[ $# -gt 0 ]] || { echo "--description requires a value" >&2; exit 1; }
      DESCRIPTION="$1"
      ;;
    --template)
      shift
      [[ $# -gt 0 ]] || { echo "--template requires a value" >&2; exit 1; }
      TEMPLATE="$1"
      ;;
    --no-apply-policy)
      APPLY_POLICY=0
      ;;
    --allow-private-policy)
      ALLOW_PRIVATE_POLICY=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY_SCRIPT="$SCRIPT_DIR/apply_one_repo_policy.sh"

if [[ "$APPLY_POLICY" -eq 1 && ! -x "$APPLY_SCRIPT" ]]; then
  echo "Missing executable script: $APPLY_SCRIPT" >&2
  echo "Run: chmod +x $APPLY_SCRIPT" >&2
  exit 1
fi

echo "Checking GitHub auth..."
gh auth status >/dev/null

full_repo="$ORG/$REPO"

if [[ "$DRY_RUN" -eq 1 ]]; then
  create_cmd=(gh repo create "$full_repo" "--$VISIBILITY" --clone=false)
  [[ -n "$DESCRIPTION" ]] && create_cmd+=(--description "$DESCRIPTION")
  [[ -n "$TEMPLATE" ]] && create_cmd+=(--template "$TEMPLATE")
  echo "[dry-run] existence check skipped for $full_repo"
  printf '[dry-run] '
  printf '%q ' "${create_cmd[@]}"
  echo
else
  if gh repo view "$full_repo" >/dev/null 2>&1; then
    echo "Repo exists: $full_repo"
  else
    create_cmd=(gh repo create "$full_repo" "--$VISIBILITY" --clone=false)
    [[ -n "$DESCRIPTION" ]] && create_cmd+=(--description "$DESCRIPTION")
    [[ -n "$TEMPLATE" ]] && create_cmd+=(--template "$TEMPLATE")
    "${create_cmd[@]}"
  fi
fi

if [[ "$APPLY_POLICY" -ne 1 ]]; then
  echo "Policy application disabled (--no-apply-policy)."
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  apply_cmd=("$APPLY_SCRIPT" "$ORG" "$REPO" --dry-run)
  [[ "$ALLOW_PRIVATE_POLICY" -eq 1 ]] && apply_cmd+=(--allow-private)
  printf '[dry-run] '
  printf '%q ' "${apply_cmd[@]}"
  echo
  exit 0
fi

actual_visibility="$(gh api "repos/$ORG/$REPO" --jq '.visibility')"

apply_cmd=("$APPLY_SCRIPT" "$ORG" "$REPO")
if [[ "$ALLOW_PRIVATE_POLICY" -eq 1 || "$actual_visibility" == "public" ]]; then
  [[ "$ALLOW_PRIVATE_POLICY" -eq 1 ]] && apply_cmd+=(--allow-private)
  "${apply_cmd[@]}"
else
  echo "Skipping policy for $full_repo (visibility=$actual_visibility, use --allow-private-policy to include)."
fi
