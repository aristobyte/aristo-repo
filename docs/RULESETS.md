# Rulesets

## Active rulesets (from config)
Configured in `config/management.json` under `policy.ruleset_files`:
- `policy/core-branches-ruleset.json`
- `policy/release-branches-ruleset.json`
- `policy/tag-protection-ruleset.json`

## Optional (not active by default)
- `policy/ci-gates-core-branches-ruleset.json`

This optional ruleset is intentionally `enforcement: disabled` and uses placeholder check context `ci`.
Enable and customize only after finalizing required status checks.
