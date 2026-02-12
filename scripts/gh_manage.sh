#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/gh_manage.sh <command> [--config FILE]

Commands:
  validate   Validate config and required files
  plan       Print planned operations from config
  run        Execute operations from config

Options:
  --config FILE   Path to config file (default: ./config/management.json)
  -h, --help      Show this help
USAGE
}

CONFIG_FILE="./config/management.json"
COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    validate|plan|run)
      COMMAND="$1"
      ;;
    --config)
      shift
      [[ $# -gt 0 ]] || { echo "--config requires a value" >&2; exit 1; }
      CONFIG_FILE="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

[[ -n "$COMMAND" ]] || { usage; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd jq

[[ -f "$CONFIG_FILE" ]] || { echo "Missing config file: $CONFIG_FILE" >&2; exit 1; }
jq . "$CONFIG_FILE" >/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_SCRIPT="$SCRIPT_DIR/create_repo.sh"
APPLY_ORG_SCRIPT="$SCRIPT_DIR/apply_org_policy.sh"

[[ -x "$CREATE_SCRIPT" ]] || { echo "Missing executable script: $CREATE_SCRIPT" >&2; exit 1; }
[[ -x "$APPLY_ORG_SCRIPT" ]] || { echo "Missing executable script: $APPLY_ORG_SCRIPT" >&2; exit 1; }

version="$(jq -r '.version // 0' "$CONFIG_FILE")"
[[ "$version" == "1" ]] || { echo "Unsupported config version: $version" >&2; exit 1; }

policy_dir="$(jq -r '.policy.policy_dir // "./policy"' "$CONFIG_FILE")"
ruleset_file_cfg="$(jq -r '.policy.ruleset_file // "default-branch-ruleset.json"' "$CONFIG_FILE")"
ruleset_files_cfg_json="$(jq -c '.policy.ruleset_files // []' "$CONFIG_FILE")"
ruleset_name="$(jq -r '.policy.ruleset_name // ""' "$CONFIG_FILE")"
dry_run="$(jq -r '.execution.dry_run // true' "$CONFIG_FILE")"
allow_private="$(jq -r '.execution.allow_private // false' "$CONFIG_FILE")"
max_repos="$(jq -r '.execution.max_repos_per_org // 0' "$CONFIG_FILE")"

if [[ "$ruleset_file_cfg" = /* ]]; then
  ruleset_file="$ruleset_file_cfg"
else
  ruleset_file="$policy_dir/$ruleset_file_cfg"
fi

[[ -f "$policy_dir/repo-settings.json" ]] || { echo "Missing file: $policy_dir/repo-settings.json" >&2; exit 1; }
[[ -f "$ruleset_file" ]] || { echo "Missing file: $ruleset_file" >&2; exit 1; }

resolved_ruleset_files=()
if jq -e '.policy.ruleset_files // [] | type == "array" and length > 0' "$CONFIG_FILE" >/dev/null; then
  while IFS= read -r entry; do
    if [[ "$entry" = /* ]]; then
      rf="$entry"
    else
      rf="$policy_dir/$entry"
    fi
    [[ -f "$rf" ]] || { echo "Missing ruleset file: $rf" >&2; exit 1; }
    resolved_ruleset_files+=("$rf")
  done < <(jq -r '.policy.ruleset_files[]' "$CONFIG_FILE")
else
  resolved_ruleset_files=("$ruleset_file")
fi

export POLICY_DIR="$policy_dir"
export REPO_SETTINGS_FILE="$policy_dir/repo-settings.json"
export RULESET_FILE="$ruleset_file"
export RULESET_FILES_JSON="$(printf '%s\n' "${resolved_ruleset_files[@]}" | jq -Rsc 'split("\n")[:-1]')"
export RULESET_NAME="$ruleset_name"

print_plan() {
  echo "Config: $CONFIG_FILE"
  echo "policy_dir=$policy_dir"
  echo "ruleset_file=$ruleset_file"
  echo "ruleset_files:"
  for rf in "${resolved_ruleset_files[@]}"; do
    echo "- $rf"
  done
  echo "ruleset_name=$ruleset_name"
  echo "dry_run=$dry_run"
  echo "allow_private=$allow_private"
  echo "max_repos_per_org=$max_repos"
  echo

  echo "Create repos:"
  if jq -e '.operations.create_repos | length > 0' "$CONFIG_FILE" >/dev/null; then
    jq -r '.operations.create_repos[] | "- \(.org)/\(.name) visibility=\(.visibility // "public") apply_policy=\(.apply_policy // true)"' "$CONFIG_FILE"
  else
    echo "- none"
  fi

  echo
  echo "Apply org policy:"
  if [[ "$(jq -r '.operations.apply_org_policy.enabled // false' "$CONFIG_FILE")" == "true" ]]; then
    jq -r '.operations.apply_org_policy.orgs[]? | "- \(.)"' "$CONFIG_FILE"
  else
    echo "- disabled"
  fi
}

validate_only() {
  jq -e '.operations.create_repos // [] | type == "array"' "$CONFIG_FILE" >/dev/null
  jq -e '.operations.apply_org_policy // {} | type == "object"' "$CONFIG_FILE" >/dev/null
  jq -e '.operations.apply_org_policy.orgs // [] | type == "array"' "$CONFIG_FILE" >/dev/null
  echo "Validation OK"
}

run_create_repos() {
  while IFS= read -r item; do
    org="$(jq -r '.org' <<<"$item")"
    name="$(jq -r '.name' <<<"$item")"
    visibility="$(jq -r '.visibility // "public"' <<<"$item")"
    description="$(jq -r '.description // ""' <<<"$item")"
    template="$(jq -r '.template // ""' <<<"$item")"
    apply_policy="$(jq -r '.apply_policy // true' <<<"$item")"

    cmd=("$CREATE_SCRIPT" "$org" "$name")
    if [[ "$visibility" == "private" ]]; then
      cmd+=(--private)
    else
      cmd+=(--public)
    fi
    [[ -n "$description" ]] && cmd+=(--description "$description")
    [[ -n "$template" ]] && cmd+=(--template "$template")
    [[ "$apply_policy" != "true" ]] && cmd+=(--no-apply-policy)
    [[ "$allow_private" == "true" ]] && cmd+=(--allow-private-policy)
    [[ "$dry_run" == "true" ]] && cmd+=(--dry-run)

    printf 'Running: '
    printf '%q ' "${cmd[@]}"
    echo
    "${cmd[@]}"
  done < <(jq -c '.operations.create_repos[]?' "$CONFIG_FILE")
}

run_apply_org() {
  enabled="$(jq -r '.operations.apply_org_policy.enabled // false' "$CONFIG_FILE")"
  [[ "$enabled" == "true" ]] || return 0

  orgs=()
  while IFS= read -r org; do
    [[ -n "$org" ]] && orgs+=("$org")
  done < <(jq -r '.operations.apply_org_policy.orgs[]?' "$CONFIG_FILE")
  [[ ${#orgs[@]} -gt 0 ]] || { echo "apply_org_policy enabled but no orgs configured" >&2; exit 1; }

  cmd=("$APPLY_ORG_SCRIPT")
  [[ "$allow_private" == "true" ]] && cmd+=(--allow-private)
  [[ "$dry_run" == "true" ]] && cmd+=(--dry-run)
  if [[ "$max_repos" =~ ^[0-9]+$ ]] && [[ "$max_repos" -gt 0 ]]; then
    cmd+=(--max-repos "$max_repos")
  fi
  cmd+=("${orgs[@]}")

  printf 'Running: '
  printf '%q ' "${cmd[@]}"
  echo
  "${cmd[@]}"
}

case "$COMMAND" in
  validate)
    validate_only
    ;;
  plan)
    validate_only
    print_plan
    ;;
  run)
    validate_only
    print_plan
    echo
    run_create_repos
    run_apply_org
    ;;
  *)
    usage
    exit 1
    ;;
esac
