#!/usr/bin/env node

import { Command } from "commander";
import { spawnSync } from "node:child_process";
import { info, LogMode } from "./log.js";
import { runScript } from "./runner.js";

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
    await runScript({
      script: "scripts/end/create_repo.sh",
      args: [org, repo],
      mode: logMode()
    });
  });

program
  .command("apply-org")
  .description("Apply configured modules to all repos in one org")
  .argument("<org>", "GitHub organization")
  .action(async (org: string) => {
    await runScript({
      script: "scripts/end/apply_org_config.sh",
      args: [org],
      mode: logMode()
    });
  });

program
  .command("init-teams")
  .description("Create/update managed teams for one org")
  .argument("<org>", "GitHub organization")
  .action(async (org: string) => {
    await runScript({
      script: "scripts/end/init_org_teams.sh",
      args: [org],
      mode: logMode()
    });
  });

program
  .command("remove-teams")
  .description("Remove managed teams for one org")
  .argument("<org>", "GitHub organization")
  .action(async (org: string) => {
    await runScript({
      script: "scripts/end/remove_org_teams.sh",
      args: [org],
      mode: logMode()
    });
  });

program
  .command("validate")
  .description("Validate local JSON configs and shell scripts")
  .action(async () => {
    await runScript({
      script: "scripts/validate_project.sh",
      mode: logMode()
    });
  });

program
  .command("exec")
  .description("Execute any internal shell module under scripts/ with colored logs")
  .argument("<script>", "script path relative to repo root, e.g. scripts/update_rulesets_org.sh")
  .argument("[args...]", "arguments to pass to the script")
  .action(async (script: string, args: string[] = []) => {
    await runScript({
      script,
      args,
      mode: logMode()
    });
  });

program
  .command("doctor")
  .description("Quick environment checks for gh/jq/bash")
  .action(() => {
    const mode = logMode();
    const checks = ["gh", "jq", "bash"];

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
