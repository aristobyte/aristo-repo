# Architecture

## Layer 0: CLI Package
- `package.json`
- `tsconfig.json`
- `src/*`
- `dist/*` (build output)

`aristo-repo` (TypeScript npm package) is the primary operator interface.
It invokes shell end-commands and provides colorized developer-friendly logs.

## Layer 1: End Commands
- `scripts/end/create_repo.sh`
- `scripts/end/apply_org_config.sh`
- `scripts/end/init_org_teams.sh`
- `scripts/end/remove_org_teams.sh`

These are stable entrypoints for day-to-day operations.

## Layer 2: Internal Modules
Repo-scoped:
- `scripts/update_rulesets_repo.sh`
- `scripts/update_actions_policy_repo.sh`
- `scripts/update_security_policy_repo.sh`
- `scripts/update_environments_repo.sh`
- `scripts/init_discussions_repo.sh`

Org-scoped:
- `scripts/update_rulesets_org.sh`
- `scripts/update_actions_policy_org.sh`
- `scripts/update_security_policy_org.sh`
- `scripts/update_environments_org.sh`
- `scripts/init_discussions_org.sh`
- `scripts/init_teams.sh`
- `scripts/remove_teams_org.sh`

## Layer 3: Config
- `config/app.config.json` controls toggles and runtime defaults.
- feature-specific config files store module data.

## Principle
End commands call internal modules; internal modules read config only.
