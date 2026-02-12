#!/usr/bin/env bash
set -euo pipefail

# End command 3: create/update teams in org from teams config.

ORG="${1:-}"
[[ -n "$ORG" ]] || { echo "Usage: bash scripts/end/init_org_teams.sh <org>" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_CFG="$ROOT_DIR/config/app.config.json"
source "$ROOT_DIR/scripts/lib/common.sh"

command -v jq >/dev/null 2>&1 || { echo "Missing jq" >&2; exit 1; }
[[ -f "$APP_CFG" ]] || { echo "Missing app config: $APP_CFG" >&2; exit 1; }

teams_enabled="$(jq -r '.modules.teams.enabled // true' "$APP_CFG")"
[[ "$teams_enabled" == "true" ]] || { echo "Teams module disabled in app config"; exit 0; }

teams_cfg="$(common_resolve_path_from_root "$ROOT_DIR" "$(jq -r '.modules.teams.config // "./config/teams.config.json"' "$APP_CFG")")"
dry_run="$(jq -r '.defaults.dry_run // false' "$APP_CFG")"

cmd=(bash "$ROOT_DIR/scripts/init_teams.sh" --config "$teams_cfg" --org "$ORG")
[[ "$dry_run" == "true" ]] && cmd+=(--dry-run)
"${cmd[@]}"
