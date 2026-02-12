#!/usr/bin/env bash

# Shared helpers for aristo-repo scripts.

common_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    return 1
  }
}

common_require_gh_jq() {
  common_require_cmd gh
  common_require_cmd jq
}

common_check_gh_auth() {
  echo "Checking GitHub auth..."
  gh auth status >/dev/null
}

common_bool_true() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

common_repo_list_tsv() {
  # Args: ORG [LIMIT]
  local org="$1"
  local limit="${2:-200}"
  gh repo list "$org" --limit "$limit" --json name,visibility,isArchived \
    --jq '.[] | [.name, .visibility, (.isArchived|tostring)] | @tsv'
}

common_parse_repo_full() {
  # Args: ORG/REPO
  local full="$1"
  [[ "$full" == */* ]] || {
    echo "Invalid repo format '$full' (expected ORG/REPO)" >&2
    return 1
  }
  printf '%s\n' "${full%%/*}" "${full##*/}"
}

common_resolve_path_from_root() {
  # Args: ROOT maybe_relative_or_absolute
  local root="$1"
  local p="$2"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s/%s\n' "$root" "${p#./}"
  fi
}
