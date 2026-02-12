#!/usr/bin/env bash
set -euo pipefail

# End command 2: apply all config modules to all repos in org.

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/end/apply_org_config.sh <org>
USAGE
}

ORG="${1:-}"
[[ -n "$ORG" ]] || { usage; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_CFG="$ROOT_DIR/config/app.config.json"
source "$ROOT_DIR/scripts/lib/common.sh"

command -v jq >/dev/null 2>&1 || { echo "Missing jq" >&2; exit 1; }
[[ -f "$APP_CFG" ]] || { echo "Missing app config: $APP_CFG" >&2; exit 1; }

DRY_RUN="$(jq -r '.defaults.dry_run // false' "$APP_CFG")"
ALLOW_PRIVATE="$(jq -r '.defaults.allow_private // true' "$APP_CFG")"
INCLUDE_ARCHIVED="$(jq -r '.defaults.include_archived // false' "$APP_CFG")"
MAX_REPOS="$(jq -r '.defaults.max_repos // 0' "$APP_CFG")"

enable_rulesets="$(jq -r '.modules.rulesets.enabled // true' "$APP_CFG")"
enable_discussions="$(jq -r '.modules.discussions.enabled // true' "$APP_CFG")"
enable_actions="$(jq -r '.modules.actions.enabled // true' "$APP_CFG")"
enable_security="$(jq -r '.modules.security.enabled // true' "$APP_CFG")"
enable_environments="$(jq -r '.modules.environments.enabled // true' "$APP_CFG")"

rulesets_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.rulesets.config // "./config/management.json"' "$APP_CFG")")"
discussions_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.discussions.config // "./config/discussions.config.json"' "$APP_CFG")")"
actions_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.actions.config // "./config/actions.config.json"' "$APP_CFG")")"
security_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.security.config // "./config/security.config.json"' "$APP_CFG")")"
environments_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.environments.config // "./config/environments.config.json"' "$APP_CFG")")"

common_flags=()
[[ "$ALLOW_PRIVATE" == "true" ]] && common_flags+=(--allow-private)
[[ "$INCLUDE_ARCHIVED" == "true" ]] && common_flags+=(--include-archived)
[[ "$DRY_RUN" == "true" ]] && common_flags+=(--dry-run)
if [[ "$MAX_REPOS" =~ ^[0-9]+$ ]] && [[ "$MAX_REPOS" -gt 0 ]]; then
  common_flags+=(--max-repos "$MAX_REPOS")
fi

if [[ "$enable_rulesets" == "true" ]]; then
  cmd=(bash "$ROOT_DIR/scripts/update_rulesets_org.sh" --org "$ORG" --config "$rulesets_cfg")
  [[ "$ALLOW_PRIVATE" == "true" ]] && cmd+=(--allow-private)
  [[ "$DRY_RUN" == "true" ]] && cmd+=(--dry-run)
  if [[ "$MAX_REPOS" =~ ^[0-9]+$ ]] && [[ "$MAX_REPOS" -gt 0 ]]; then
    cmd+=(--max-repos "$MAX_REPOS")
  fi
  "${cmd[@]}"
fi

if [[ "$enable_actions" == "true" ]]; then
  bash "$ROOT_DIR/scripts/update_actions_policy_org.sh" --org "$ORG" --config "$actions_cfg" "${common_flags[@]}"
fi

if [[ "$enable_security" == "true" ]]; then
  bash "$ROOT_DIR/scripts/update_security_policy_org.sh" --org "$ORG" --config "$security_cfg" "${common_flags[@]}"
fi

if [[ "$enable_environments" == "true" ]]; then
  bash "$ROOT_DIR/scripts/update_environments_org.sh" --org "$ORG" --config "$environments_cfg" "${common_flags[@]}"
fi

if [[ "$enable_discussions" == "true" ]]; then
  cmd=(bash "$ROOT_DIR/scripts/init_discussions_org.sh" --org "$ORG" --config "$discussions_cfg")
  [[ "$ALLOW_PRIVATE" == "true" ]] && cmd+=(--allow-private)
  [[ "$INCLUDE_ARCHIVED" == "true" ]] && cmd+=(--include-archived)
  [[ "$DRY_RUN" == "true" ]] && cmd+=(--dry-run)
  if [[ "$MAX_REPOS" =~ ^[0-9]+$ ]] && [[ "$MAX_REPOS" -gt 0 ]]; then
    cmd+=(--max-repos "$MAX_REPOS")
  fi
  "${cmd[@]}"
fi
