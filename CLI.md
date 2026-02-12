# aristo-repo

TypeScript CLI package for managing AristoByte GitHub org/repo setup from one command.

## Install (local dev)

```bash
cd ./aristo-repo
npm install
npm run build
npm link
```

Then use globally in your shell:

```bash
aristo-repo --help
```

## Commands

```bash
aristo-repo create <org> <repo>
aristo-repo apply-org <org>
aristo-repo init-teams <org>
aristo-repo remove-teams <org>
aristo-repo validate
aristo-repo exec <script> [args...]
aristo-repo doctor
```

## Implementation Notes

- `create`, `apply-org`, `init-teams`, `remove-teams`, `validate` are handled directly by TS CLI flow code.
- `exec` remains the escape hatch for running compatibility command ids (`scripts/...` legacy ids are accepted).
- Script compatibility entrypoints now use `.ts` paths.

## Colored Output

The CLI colorizes shell script output by semantic patterns:

- errors/warnings/skips/dry-run
- repo headers (`==> ...`)
- create/update/delete success lines
- summaries and validation lines

Use plain output if needed:

```bash
aristo-repo --plain apply-org aristobyte
```
