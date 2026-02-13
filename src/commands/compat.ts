import path from "node:path";
import {
  REPO_ROOT,
  applyActionsOrg,
  applyActionsRepo,
  applyEnvironmentsOrg,
  applyEnvironmentsRepo,
  applyOneRepoPolicy,
  applyOrgPolicy,
  applyRulesetsOrg,
  applyRulesetsRepo,
  applySecurityOrg,
  applySecurityRepo,
  createRepoCore,
  ensureDiscussionsOrg,
  ensureDiscussionsRepo,
  ensureOrgTeams,
  initTeams,
  loadJsonFile,
  removeTeams,
  resolvePathFromRoot,
  runApplyOrgFlow,
  runCreateFlow,
  runInitTeamsFlow,
  runManage,
  runRemoveTeamsFlow,
  runValidateFlow,
  toBool
} from "../app.js";
import { hasFlag, parseFlagValue, parseIntFlag, parseOrgList } from "../utils/flags.js";

type OrgConfig = {
  org?: string;
  execution?: {
    include_private?: boolean;
    include_archived?: boolean;
  };
};

export async function runCompatScript(scriptInput: string, args: string[]): Promise<void> {
  const script = scriptInput.replace(/^\.\//, "");
  const normalized = script.startsWith("src/") ? script.slice(4) : script;

  switch (normalized) {
    case "scripts/end/create_repo.sh":
    case "scripts/end/create_repo.ts": {
      const org = args[0];
      const repo = args[1];
      if (!org || !repo) {
        throw new Error("Usage: create_repo <org> <repo>");
      }
      await runCreateFlow(org, repo);
      return;
    }

    case "scripts/end/apply_org_config.sh":
    case "scripts/end/apply_org_config.ts": {
      const org = args[0];
      if (!org) {
        throw new Error("Usage: apply_org_config <org>");
      }
      await runApplyOrgFlow(org);
      return;
    }

    case "scripts/end/init_org_teams.sh":
    case "scripts/end/init_org_teams.ts": {
      const org = args[0];
      if (!org) {
        throw new Error("Usage: init_org_teams <org>");
      }
      await runInitTeamsFlow(org);
      return;
    }

    case "scripts/end/remove_org_teams.sh":
    case "scripts/end/remove_org_teams.ts": {
      const org = args[0];
      if (!org) {
        throw new Error("Usage: remove_org_teams <org>");
      }
      await runRemoveTeamsFlow(org);
      return;
    }

    case "scripts/validate_project.sh":
    case "scripts/validate_project.ts": {
      runValidateFlow();
      return;
    }

    case "scripts/update_rulesets_repo.sh":
    case "scripts/update_rulesets_repo.ts": {
      const repoFull = parseFlagValue(args, "--repo");
      const configFile = resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/management.json"));
      applyRulesetsRepo(repoFull, configFile, {
        dryRun: hasFlag(args, "--dry-run"),
        bypassTeamSlug: parseFlagValue(args, "--bypass-team-slug", "aristo-bypass"),
        reviewerTeamSlug: parseFlagValue(args, "--reviewer-team-slug", "aristobyte-approvers")
      });
      return;
    }

    case "scripts/update_rulesets_org.sh":
    case "scripts/update_rulesets_org.ts": {
      const org = parseFlagValue(args, "--org");
      const configFile = resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/management.json"));
      applyRulesetsOrg(org, configFile, {
        dryRun: hasFlag(args, "--dry-run"),
        allowPrivate: hasFlag(args, "--allow-private"),
        maxRepos: parseIntFlag(args, "--max-repos", 0),
        bypassTeamSlug: parseFlagValue(args, "--bypass-team-slug", "aristo-bypass"),
        reviewerTeamSlug: parseFlagValue(args, "--reviewer-team-slug", "aristobyte-approvers")
      });
      return;
    }

    case "scripts/update_actions_policy_repo.sh":
    case "scripts/update_actions_policy_repo.ts": {
      applyActionsRepo(
        parseFlagValue(args, "--repo"),
        resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/actions.config.json")),
        hasFlag(args, "--dry-run")
      );
      return;
    }

    case "scripts/update_actions_policy_org.sh":
    case "scripts/update_actions_policy_org.ts": {
      const configFile = resolvePathFromRoot(
        REPO_ROOT,
        parseFlagValue(args, "--config", "./config/actions.config.json")
      );
      const config = loadJsonFile<OrgConfig>(configFile);
      const org = parseFlagValue(args, "--org", config.org ?? "");
      if (!org) {
        throw new Error("Missing .org in config and --org was not provided");
      }
      applyActionsOrg(org, configFile, {
        dryRun: hasFlag(args, "--dry-run"),
        allowPrivate: hasFlag(args, "--allow-private") || toBool(config.execution?.include_private, true),
        includeArchived: hasFlag(args, "--include-archived") || toBool(config.execution?.include_archived, false),
        maxRepos: parseIntFlag(args, "--max-repos", 0)
      });
      return;
    }

    case "scripts/update_security_policy_repo.sh":
    case "scripts/update_security_policy_repo.ts": {
      applySecurityRepo(
        parseFlagValue(args, "--repo"),
        resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/security.config.json")),
        hasFlag(args, "--dry-run")
      );
      return;
    }

    case "scripts/update_security_policy_org.sh":
    case "scripts/update_security_policy_org.ts": {
      const configFile = resolvePathFromRoot(
        REPO_ROOT,
        parseFlagValue(args, "--config", "./config/security.config.json")
      );
      const config = loadJsonFile<OrgConfig>(configFile);
      const org = parseFlagValue(args, "--org", config.org ?? "");
      if (!org) {
        throw new Error("Missing .org in config and --org was not provided");
      }
      applySecurityOrg(org, configFile, {
        dryRun: hasFlag(args, "--dry-run"),
        allowPrivate: hasFlag(args, "--allow-private") || toBool(config.execution?.include_private, true),
        includeArchived: hasFlag(args, "--include-archived") || toBool(config.execution?.include_archived, false),
        maxRepos: parseIntFlag(args, "--max-repos", 0)
      });
      return;
    }

    case "scripts/update_environments_repo.sh":
    case "scripts/update_environments_repo.ts": {
      applyEnvironmentsRepo(
        parseFlagValue(args, "--repo"),
        resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/environments.config.json")),
        hasFlag(args, "--dry-run")
      );
      return;
    }

    case "scripts/update_environments_org.sh":
    case "scripts/update_environments_org.ts": {
      const configFile = resolvePathFromRoot(
        REPO_ROOT,
        parseFlagValue(args, "--config", "./config/environments.config.json")
      );
      const config = loadJsonFile<OrgConfig>(configFile);
      const org = parseFlagValue(args, "--org", config.org ?? "");
      if (!org) {
        throw new Error("Missing .org in config and --org was not provided");
      }
      applyEnvironmentsOrg(org, configFile, {
        dryRun: hasFlag(args, "--dry-run"),
        allowPrivate: hasFlag(args, "--allow-private") || toBool(config.execution?.include_private, true),
        includeArchived: hasFlag(args, "--include-archived") || toBool(config.execution?.include_archived, false),
        maxRepos: parseIntFlag(args, "--max-repos", 0)
      });
      return;
    }

    case "scripts/init_discussions_repo.sh":
    case "scripts/init_discussions_repo.ts": {
      ensureDiscussionsRepo(
        parseFlagValue(args, "--repo"),
        resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/discussions.config.json")),
        hasFlag(args, "--dry-run")
      );
      return;
    }

    case "scripts/init_discussions_org.sh":
    case "scripts/init_discussions_org.ts": {
      const org = parseFlagValue(args, "--org");
      ensureDiscussionsOrg(
        org,
        resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/discussions.config.json")),
        {
          dryRun: hasFlag(args, "--dry-run"),
          allowPrivate: hasFlag(args, "--allow-private"),
          includeArchived: hasFlag(args, "--include-archived"),
          maxRepos: parseIntFlag(args, "--max-repos", 0)
        }
      );
      return;
    }

    case "scripts/init_teams.sh":
    case "scripts/init_teams.ts": {
      const configFile = resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/teams.config.json"));
      const config = loadJsonFile<OrgConfig>(configFile);
      const org = parseFlagValue(args, "--org", config.org ?? "");
      if (!org) {
        throw new Error("Missing .org in config and --org was not provided");
      }
      initTeams(org, configFile, {
        dryRun: hasFlag(args, "--dry-run"),
        includeArchived: hasFlag(args, "--include-archived"),
        maxRepos: parseIntFlag(args, "--max-repos", 0)
      });
      return;
    }

    case "scripts/remove_teams_org.sh":
    case "scripts/remove_teams_org.ts": {
      const org = parseFlagValue(args, "--org");
      removeTeams(
        org,
        resolvePathFromRoot(REPO_ROOT, parseFlagValue(args, "--config", "./config/teams.config.json")),
        hasFlag(args, "--dry-run")
      );
      return;
    }

    case "scripts/ensure_org_teams.sh":
    case "scripts/ensure_org_teams.ts": {
      const org = args[0];
      if (!org || org.startsWith("--")) {
        throw new Error("Usage: ensure_org_teams <org> [--owner-user USER] [--dry-run]");
      }
      ensureOrgTeams(org, {
        ownerUser: parseFlagValue(args, "--owner-user", "aristobyte-team"),
        dryRun: hasFlag(args, "--dry-run")
      });
      return;
    }

    case "scripts/apply_one_repo_policy.sh":
    case "scripts/apply_one_repo_policy.ts":
    case "apply_one_repo_policy.sh":
    case "apply_one_repo_policy.ts": {
      const org = args[0];
      const repo = args[1];
      if (!org || !repo || org.startsWith("--") || repo.startsWith("--")) {
        throw new Error("Usage: apply_one_repo_policy <org> <repo> [options]");
      }
      const rest = args.slice(2);
      applyOneRepoPolicy(`${org}/${repo}`, {
        configFile: path.resolve(REPO_ROOT, "config/management.json"),
        allowPrivate: hasFlag(rest, "--allow-private"),
        repoVisibility: parseFlagValue(rest, "--repo-visibility", ""),
        repoArchived: parseFlagValue(rest, "--repo-archived", ""),
        dryRun: hasFlag(rest, "--dry-run"),
        bypassTeamSlug: "aristo-bypass",
        reviewerTeamSlug: "aristobyte-approvers"
      });
      return;
    }

    case "scripts/create_repo.sh":
    case "scripts/create_repo.ts": {
      const org = args[0];
      const repo = args[1];
      if (!org || !repo || org.startsWith("--") || repo.startsWith("--")) {
        throw new Error("Usage: create_repo <org> <repo> [options]");
      }
      const rest = args.slice(2);
      createRepoCore(org, repo, {
        visibility: hasFlag(rest, "--private") ? "private" : "public",
        description: parseFlagValue(rest, "--description", ""),
        template: parseFlagValue(rest, "--template", ""),
        applyPolicy: !hasFlag(rest, "--no-apply-policy"),
        allowPrivatePolicy: hasFlag(rest, "--allow-private-policy"),
        dryRun: hasFlag(rest, "--dry-run"),
        configFile: path.resolve(REPO_ROOT, "config/management.json")
      });
      return;
    }

    case "scripts/apply_org_policy.sh":
    case "scripts/apply_org_policy.ts": {
      const orgs = parseOrgList(args);
      applyOrgPolicy(orgs.length > 0 ? orgs : ["aristobyte", "aristobyte-ui"], {
        allowPrivate: hasFlag(args, "--allow-private"),
        dryRun: hasFlag(args, "--dry-run"),
        maxRepos: parseIntFlag(args, "--max-repos", 0),
        configFile: path.resolve(REPO_ROOT, "config/management.json")
      });
      return;
    }

    case "scripts/gh_manage.sh":
    case "scripts/gh_manage.ts":
    case "manage.sh":
    case "manage.ts": {
      const command = (args.find((a) => ["validate", "plan", "run"].includes(a)) ?? "") as
        | "validate"
        | "plan"
        | "run"
        | "";
      if (!command) {
        throw new Error("Usage: gh_manage <validate|plan|run> [--config FILE]");
      }
      runManage(command, parseFlagValue(args, "--config", "./config/management.json"));
      return;
    }

    default:
      throw new Error(`Unsupported script path: ${scriptInput}`);
  }
}
