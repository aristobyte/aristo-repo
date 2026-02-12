# AristoRepo

Clean, config-first GitHub org/repo bootstrap toolkit.

## CLI (Primary)

Use the TypeScript CLI package `aristo-repo` as the main entrypoint.

```bash
cd aristo-repo
npm install
npm run build
npm link
```

Then:

```bash
aristo-repo create <org> <repo>
aristo-repo apply-org <org>
aristo-repo init-teams <org>
aristo-repo remove-teams <org>
aristo-repo validate
```

Detailed CLI docs: `./CLI.md`

## Shell End Commands

These are still available and are used internally by the CLI.

1. Create one repo + apply repo bootstrap

```bash
bash ./scripts/end/create_repo.sh <org> <repo>
```

2. Apply all config modules to all repos in org

```bash
bash ./scripts/end/apply_org_config.sh <org>
```

3. Create/update teams in org

```bash
bash ./scripts/end/init_org_teams.sh <org>
```

4. Remove managed teams in org

```bash
bash ./scripts/end/remove_org_teams.sh <org>
```

5. Validate local project config + scripts

```bash
bash ./scripts/validate_project.sh
```

## Source of Truth

- Runtime/module toggles: `./config/app.config.json`
- Repo/rulesets policy: `./config/management.json`, `./policy/*.json`
- Teams: `./config/teams.config.json`
- Actions: `./config/actions.config.json`
- Security: `./config/security.config.json`
- Environments: `./config/environments.config.json`
- Discussions template: `./config/discussions.config.json`

## Architecture

- `scripts/end/*`: end-use orchestration commands
- `scripts/update_*_repo.sh`: repo-scoped internal modules
- `scripts/update_*_org.sh`: org-wide internal modules
- `scripts/init_*`: specialized initializers (discussions, teams)

## Notes

- Internal scripts are reusable building blocks; avoid calling them unless needed.
- `dry_run` is controlled from `config/app.config.json`.
