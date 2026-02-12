#!/usr/bin/env bash
set -euo pipefail

# End command 1: create repo + apply all repo-level bootstrap modules.
# Dynamic params accepted: ORG REPO

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/end/create_repo.sh <org> <repo>
USAGE
}

ORG="${1:-}"
REPO="${2:-}"
[[ -n "$ORG" && -n "$REPO" ]] || { usage; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_CFG="$ROOT_DIR/config/app.config.json"
source "$ROOT_DIR/scripts/lib/common.sh"

command -v jq >/dev/null 2>&1 || { echo "Missing jq" >&2; exit 1; }
[[ -f "$APP_CFG" ]] || { echo "Missing app config: $APP_CFG" >&2; exit 1; }

DRY_RUN="$(jq -r '.defaults.dry_run // false' "$APP_CFG")"

enable_repo_create="$(jq -r '.modules.repo_create.enabled // true' "$APP_CFG")"
enable_rulesets="$(jq -r '.modules.rulesets.enabled // true' "$APP_CFG")"
enable_discussions="$(jq -r '.modules.discussions.enabled // true' "$APP_CFG")"
enable_actions="$(jq -r '.modules.actions.enabled // true' "$APP_CFG")"
enable_security="$(jq -r '.modules.security.enabled // true' "$APP_CFG")"
enable_environments="$(jq -r '.modules.environments.enabled // true' "$APP_CFG")"

repo_visibility="$(jq -r '.modules.repo_create.visibility // "public"' "$APP_CFG")"
repo_description="$(jq -r '.modules.repo_create.description // ""' "$APP_CFG")"
repo_template="$(jq -r '.modules.repo_create.template // ""' "$APP_CFG")"
apply_repo_policy="$(jq -r '.modules.repo_create.apply_repo_policy // true' "$APP_CFG")"

rulesets_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.rulesets.config // "./config/management.json"' "$APP_CFG")")"
discussions_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.discussions.config // "./config/discussions.config.json"' "$APP_CFG")")"
actions_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.actions.config // "./config/actions.config.json"' "$APP_CFG")")"
security_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.security.config // "./config/security.config.json"' "$APP_CFG")")"
environments_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.environments.config // "./config/environments.config.json"' "$APP_CFG")")"

optional_failures=()

run_required() {
  local step="$1"
  shift
  if "$@"; then
    return 0
  fi
  echo "[error] required step failed: $step" >&2
  exit 1
}

run_optional() {
  local step="$1"
  shift
  if "$@"; then
    return 0
  fi
  echo "[warn] optional step failed: $step (continuing)" >&2
  optional_failures+=("$step")
}

if [[ "$enable_repo_create" == "true" ]]; then
  cmd=(bash "$ROOT_DIR/scripts/create_repo.sh" "$ORG" "$REPO")
  if [[ "$repo_visibility" == "private" ]]; then
    cmd+=(--private)
  else
    cmd+=(--public)
  fi
  [[ -n "$repo_description" ]] && cmd+=(--description "$repo_description")
  [[ -n "$repo_template" ]] && cmd+=(--template "$repo_template")
  [[ "$apply_repo_policy" != "true" ]] && cmd+=(--no-apply-policy)
  [[ "$DRY_RUN" == "true" ]] && cmd+=(--dry-run)

  run_required "repo_create" "${cmd[@]}"
fi

if [[ "$enable_rulesets" == "true" ]]; then
  cmd=(bash "$ROOT_DIR/scripts/update_rulesets_repo.sh" --repo "$ORG/$REPO" --config "$rulesets_cfg")
  [[ "$DRY_RUN" == "true" ]] && cmd+=(--dry-run)
  run_required "rulesets" "${cmd[@]}"
fi

if [[ "$enable_discussions" == "true" ]]; then
  cmd=(bash "$ROOT_DIR/scripts/init_discussions_repo.sh" --config "$discussions_cfg" --repo "$ORG/$REPO")
  [[ "$DRY_RUN" == "true" ]] && cmd+=(--dry-run)
  run_optional "discussions" "${cmd[@]}"
fi

if [[ "$enable_actions" == "true" ]]; then
  cmd=(bash "$ROOT_DIR/scripts/update_actions_policy_repo.sh" --repo "$ORG/$REPO" --config "$actions_cfg")
  [[ "$DRY_RUN" == "true" ]] && cmd+=(--dry-run)
  run_optional "actions" "${cmd[@]}"
fi

if [[ "$enable_security" == "true" ]]; then
  cmd=(bash "$ROOT_DIR/scripts/update_security_policy_repo.sh" --repo "$ORG/$REPO" --config "$security_cfg")
  [[ "$DRY_RUN" == "true" ]] && cmd+=(--dry-run)
  run_optional "security" "${cmd[@]}"
fi

if [[ "$enable_environments" == "true" ]]; then
  cmd=(bash "$ROOT_DIR/scripts/update_environments_repo.sh" --repo "$ORG/$REPO" --config "$environments_cfg")
  [[ "$DRY_RUN" == "true" ]] && cmd+=(--dry-run)
  run_optional "environments" "${cmd[@]}"
fi

if [[ ${#optional_failures[@]} -gt 0 ]]; then
  echo "[warn] create flow completed with optional failures: ${optional_failures[*]}"
else
  echo "Done: create flow completed for $ORG/$REPO"
fi
