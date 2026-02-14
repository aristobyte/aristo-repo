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

## Build And Publish

```bash
npm run check
npm run build
npm run publish:npm
```

One-step publish flow:

```bash
npm run release
```

Shell scripts (under `./scripts/`):

```bash
bash ./scripts/compile.sh
bash ./scripts/pack.sh
bash ./scripts/bump.sh patch
bash ./scripts/publish.sh
```

Detailed CLI docs: `./CLI.md`

## Current TS Migration Status

The CLI is now TS-native for:

- `create` orchestration
- `apply-org` orchestration
- `validate` checks
- Actions policy application (repo + org flows)
- Security policy application (repo + org flows)
- Environments policy application (repo + org flows)

The repository is now TS-only for operational logic.

## Compatibility Commands

Use `aristo-repo exec` with legacy command ids for backward compatibility.

```bash
aristo-repo exec scripts/update_rulesets_org.ts --org aristobyte --config ./config/management.json
aristo-repo exec scripts/validate_project.ts
```

## Source of Truth

- Runtime/module toggles: `./config/app.config.json`
- Repo/rulesets policy: `./config/management.json`, `./config/repo-settings.config.json`, `./config/rulesets.config.json`
- Teams: `./config/teams.config.json`
- Actions: `./config/actions.config.json`
- Security: `./config/security.config.json`
- Environments: `./config/environments.config.json`
- Discussions template: `./config/discussions.config.json`

## Architecture

- `src/*`: primary TS CLI and module logic
- `src/commands/*`: command/compat dispatch layer
- `src/utils/*`: shared utility helpers
- `scripts/`: Bash automation scripts used by CI/release and local maintenance

## Notes

- Internal scripts are reusable building blocks; avoid calling them unless needed.
