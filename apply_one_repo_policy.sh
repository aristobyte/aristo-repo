#!/usr/bin/env bash
set -euo pipefail

# Backwards-compatible entrypoint.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/apply_one_repo_policy.sh" "$@"
