#!/usr/bin/env node

import { Command } from "commander";
import { spawnSync } from "node:child_process";
import { info, LogMode } from "./log.js";
import { runApplyOrgFlow, runCreateFlow, runInitTeamsFlow, runRemoveTeamsFlow, runValidateFlow } from "./app.js";
import { runCompatScript } from "./commands/compat.js";

const program = new Command();

program
  .name("aristo-repo")
  .description("AristoByte GitHub management CLI")
  .version("0.1.0")
  .option("--plain", "disable colored output", false);

function logMode(): LogMode {
  const opts = program.opts<{ plain: boolean }>();
  return opts.plain ? "plain" : "color";
}

program
  .command("create")
  .description("Create one repo and apply bootstrap modules")
  .argument("<org>", "GitHub organization")
  .argument("<repo>", "repository name")
  .action(async (org: string, repo: string) => {
    await runCreateFlow(org, repo);
  });

program
  .command("apply-org")
  .description("Apply configured modules to all repos in one org")
  .argument("<org>", "GitHub organization")
  .action(async (org: string) => {
    await runApplyOrgFlow(org);
  });

program
  .command("init-teams")
  .description("Create/update managed teams for one org")
  .argument("<org>", "GitHub organization")
  .action(async (org: string) => {
    await runInitTeamsFlow(org);
  });

program
  .command("remove-teams")
  .description("Remove managed teams for one org")
  .argument("<org>", "GitHub organization")
  .action(async (org: string) => {
    await runRemoveTeamsFlow(org);
  });

program
  .command("validate")
  .description("Validate local JSON config files")
  .action(() => {
    runValidateFlow();
  });

program
  .command("exec")
  .description("Execute compatibility command ids (legacy script names are still accepted)")
  .argument("<script>", "compat id, e.g. scripts/update_rulesets_org.ts")
  .argument("[args...]", "arguments to pass to the script")
  .action(async (script: string, args: string[] = []) => {
    await runCompatScript(script, args);
  });

program
  .command("doctor")
  .description("Quick environment checks for gh/node")
  .action(() => {
    const mode = logMode();
    const checks = ["gh", "node"];

    for (const c of checks) {
      const result = spawnSync("bash", ["-lc", `command -v ${c}`], {
        stdio: "ignore"
      });
      const ok = result.status === 0;
      console.log(info(`${ok ? "OK" : "MISSING"} ${c}`, mode));
    }
  });

program.parseAsync(process.argv).catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err);
  console.error(message);
  process.exit(1);
});
