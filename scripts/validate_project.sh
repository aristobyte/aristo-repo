#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd jq

echo "Validating JSON configs..."
while IFS= read -r f; do
  jq . "$f" >/dev/null
  echo "  OK $f"
done < <(find "$ROOT_DIR/config" -type f -name '*.json' | sort)

echo
echo "Validating policy JSON templates..."
while IFS= read -r f; do
  jq . "$f" >/dev/null
  echo "  OK $f"
done < <(find "$ROOT_DIR/policy" -type f -name '*.json' | sort)

echo
echo "Validating shell syntax..."
while IFS= read -r f; do
  bash -n "$f"
  echo "  OK $f"
done < <(find "$ROOT_DIR/scripts" -type f -name '*.sh' | sort)

if [[ -f "$ROOT_DIR/manage.sh" ]]; then
  bash -n "$ROOT_DIR/manage.sh"
  echo "  OK $ROOT_DIR/manage.sh"
fi

if [[ -f "$ROOT_DIR/apply_one_repo_policy.sh" ]]; then
  bash -n "$ROOT_DIR/apply_one_repo_policy.sh"
  echo "  OK $ROOT_DIR/apply_one_repo_policy.sh"
fi

echo
echo "Validation complete."
