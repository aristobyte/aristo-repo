#!/usr/bin/env bash
set -euo pipefail

# Initialize discussions template (categories, labels, seed discussions) for a repository.

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/init_discussions_repo.sh --repo ORG/REPO [options]

Options:
  --config FILE   Config path (default: ./config/discussions.config.json)
  --repo ORG/REPO Target repository
  --dry-run       Print planned operations only
  -h, --help      Show help
USAGE
}

CONFIG_FILE="./config/discussions.config.json"
REPO_FULL=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      shift
      [[ $# -gt 0 ]] || { echo "--config requires a value" >&2; exit 1; }
      CONFIG_FILE="$1"
      ;;
    --repo)
      shift
      [[ $# -gt 0 ]] || { echo "--repo requires a value" >&2; exit 1; }
      REPO_FULL="$1"
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

[[ -n "$REPO_FULL" ]] || { echo "--repo is required" >&2; usage; exit 1; }
[[ "$REPO_FULL" == */* ]] || { echo "--repo must be ORG/REPO" >&2; exit 1; }
ORG="${REPO_FULL%%/*}"
REPO="${REPO_FULL##*/}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_cmd gh
require_cmd jq

[[ -f "$CONFIG_FILE" ]] || { echo "Missing config file: $CONFIG_FILE" >&2; exit 1; }
jq . "$CONFIG_FILE" >/dev/null

version="$(jq -r '.version // 0' "$CONFIG_FILE")"
[[ "$version" == "1" ]] || { echo "Unsupported config version: $version" >&2; exit 1; }

echo "Checking GitHub auth..."
gh auth status >/dev/null

repo_id="$(gh api graphql -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){id hasDiscussionsEnabled}}' -F owner="$ORG" -F name="$REPO" --jq '.data.repository.id')"
has_discussions="$(gh api graphql -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){hasDiscussionsEnabled}}' -F owner="$ORG" -F name="$REPO" --jq '.data.repository.hasDiscussionsEnabled')"

if [[ "$has_discussions" != "true" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] enable discussions for $REPO_FULL"
  else
    gh api -X PATCH "repos/$ORG/$REPO" -f has_discussions=true >/dev/null
    echo "enabled discussions: $REPO_FULL"
  fi
fi

label_id_by_name() {
  local name="$1"
  gh api graphql \
    -f query='query($owner:String!,$name:String!,$label:String!){repository(owner:$owner,name:$name){labels(first:100,query:$label){nodes{id name}}}}' \
    -F owner="$ORG" -F name="$REPO" -F label="$name" \
    --jq '.data.repository.labels.nodes[] | select(.name == "'"$name"'") | .id' | head -n1 || true
}

ensure_label() {
  local name="$1"
  local color="$2"
  local description="$3"

  local existing
  existing="$(label_id_by_name "$name")"
  if [[ -n "$existing" ]]; then
    echo "label exists: $name"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] create label: $name"
    return
  fi

  gh api -X POST "repos/$ORG/$REPO/labels" \
    -f name="$name" \
    -f color="$color" \
    -f description="$description" >/dev/null
  echo "label created: $name"
}

category_id_by_name() {
  local name="$1"
  gh api "repos/$ORG/$REPO/discussions/categories" \
    --jq '.[] | select(.name == "'"$name"'") | .id' 2>/dev/null | head -n1 || true
}

ensure_category() {
  local name="$1"
  local description="$2"
  local emoji="$3"
  local answerable="$4"

  local existing
  existing="$(category_id_by_name "$name")"
  if [[ -n "$existing" ]]; then
    echo "category exists: $name"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] create category: $name"
    return
  fi

  gh api -X POST "repos/$ORG/$REPO/discussions/categories" \
    -F name="$name" \
    -F description="$description" \
    -F emoji="$emoji" \
    -F is_answerable="$answerable" >/dev/null
  echo "category created: $name"
}

discussion_id_by_title() {
  local title="$1"
  gh api "repos/$ORG/$REPO/discussions" \
    --jq '.[] | select(.title == "'"$title"'") | .node_id' 2>/dev/null | head -n1 || true
}

create_discussion() {
  local title="$1"
  local body="$2"
  local category_name="$3"

  local existing
  existing="$(discussion_id_by_title "$title")"
  if [[ -n "$existing" ]]; then
    echo "discussion exists: $title" >&2
    printf '%s\n' "$existing"
    return
  fi

  local category_id
  category_id="$(category_id_by_name "$category_name")"
  [[ -n "$category_id" ]] || { echo "Missing category for discussion '$title': $category_name" >&2; return 1; }

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] create discussion: $title" >&2
    printf '%s\n' "DRY_RUN_ID"
    return
  fi

  local result
  if ! result="$(gh api -X POST "repos/$ORG/$REPO/discussions" \
    -F category_id="$category_id" \
    -F title="$title" \
    -F body="$body" \
    --jq '.node_id' 2>&1)"; then
    echo "[error] failed to create discussion '$title': $result" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

add_labels_to_discussion() {
  local discussion_id="$1"
  shift
  local label_ids=("$@")

  [[ "$discussion_id" != "DRY_RUN_ID" ]] || return 0
  [[ ${#label_ids[@]} -gt 0 ]] || return 0

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] add ${#label_ids[@]} labels to discussion"
    return
  fi

  local payload
  payload="$(printf '%s\n' "${label_ids[@]}" | jq -Rsc 'split("\n")[:-1]')"

  gh api graphql \
    -f query='mutation($labelableId:ID!,$labelIds:[ID!]!){addLabelsToLabelable(input:{labelableId:$labelableId,labelIds:$labelIds}){clientMutationId}}' \
    -F labelableId="$discussion_id" \
    -F labelIds="$payload" >/dev/null
}

while IFS= read -r c; do
  name="$(jq -r '.name' <<<"$c")"
  description="$(jq -r '.description // ""' <<<"$c")"
  emoji="$(jq -r '.emoji // ""' <<<"$c")"
  answerable="$(jq -r '.is_answerable // false' <<<"$c")"
  ensure_category "$name" "$description" "$emoji" "$answerable"
done < <(jq -c '.template.categories[]' "$CONFIG_FILE")

while IFS= read -r l; do
  name="$(jq -r '.name' <<<"$l")"
  color="$(jq -r '.color // "BFD4F2"' <<<"$l")"
  description="$(jq -r '.description // ""' <<<"$l")"
  ensure_label "$name" "$color" "$description"
done < <(jq -c '.template.labels[]' "$CONFIG_FILE")

while IFS= read -r d; do
  title="$(jq -r '.title' <<<"$d")"
  category="$(jq -r '.category' <<<"$d")"
  body="$(jq -r '.body' <<<"$d")"

  discussion_id="$(create_discussion "$title" "$body" "$category")"

  label_ids=()
  while IFS= read -r label_name; do
    label_id="$(label_id_by_name "$label_name")"
    [[ -n "$label_id" ]] && label_ids+=("$label_id")
  done < <(jq -r '.labels[]?' <<<"$d")

  add_labels_to_discussion "$discussion_id" "${label_ids[@]}"
done < <(jq -c '.template.initial_discussions[]' "$CONFIG_FILE")

echo "Done: discussions template initialized for $REPO_FULL"
