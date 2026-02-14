import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import fs from "node:fs";
import path from "node:path";

const THIS_FILE = fileURLToPath(import.meta.url);
const PACKAGE_ROOT = path.resolve(path.dirname(THIS_FILE), "..");

function resolveRepoRoot(): string {
  const envRoot = process.env.ARISTO_REPO_ROOT;
  if (envRoot) {
    return path.resolve(envRoot);
  }

  const cwd = process.cwd();
  const cwdConfig = path.resolve(cwd, "config/app.config.json");
  if (fs.existsSync(cwdConfig)) {
    return cwd;
  }

  const packagedDistRoot = path.resolve(PACKAGE_ROOT, "dist");
  const packagedDistConfig = path.resolve(packagedDistRoot, "config/app.config.json");
  if (fs.existsSync(packagedDistConfig)) {
    return packagedDistRoot;
  }

  const packagedConfig = path.resolve(PACKAGE_ROOT, "config/app.config.json");
  if (fs.existsSync(packagedConfig)) {
    return PACKAGE_ROOT;
  }

  return PACKAGE_ROOT;
}

export const REPO_ROOT = resolveRepoRoot();

type RepoInfo = {
  name: string;
  visibility: string;
  isArchived: boolean;
};

type AppConfig = {
  version?: number;
  defaults?: {
    preview?: boolean;
    allow_private?: boolean;
    include_archived?: boolean;
    max_repos?: number;
  };
  modules?: {
    repo_create?: {
      enabled?: boolean;
      visibility?: "public" | "private";
      description?: string;
      template?: string;
      apply_repo_policy?: boolean;
    };
    rulesets?: { enabled?: boolean; config?: string };
    discussions?: { enabled?: boolean; config?: string };
    actions?: { enabled?: boolean; config?: string };
    security?: { enabled?: boolean; config?: string };
    environments?: { enabled?: boolean; config?: string };
    teams?: { enabled?: boolean; config?: string };
  };
};

type ManagementConfig = {
  version?: number;
  execution?: {
    preview?: boolean;
    allow_private?: boolean;
    max_repos_per_org?: number;
  };
  policy?: {
    repo_settings_config?: string;
    rulesets_config?: string;
    ruleset_name?: string;
  };
  operations?: {
    create_repos?: Array<{
      org: string;
      name: string;
      visibility?: "public" | "private";
      description?: string;
      template?: string;
      apply_policy?: boolean;
    }>;
    apply_org_policy?: {
      enabled?: boolean;
      orgs?: string[];
    };
  };
};

type RepoSettingsConfig = {
  version?: number;
  settings: Record<string, unknown>;
};

type RulesetsConfig = {
  version?: number;
  rulesets: Array<Record<string, unknown>>;
};

type ActionsConfig = {
  version?: number;
  org?: string;
  execution?: { include_private?: boolean; include_archived?: boolean };
  policy?: {
    enabled?: boolean;
    allowed_actions_mode?: "all" | "local_only" | "selected";
    allow_github_owned?: boolean;
    allow_verified_creators?: boolean;
    patterns_allowed?: string[];
  };
};

type SecurityConfig = {
  version?: number;
  org?: string;
  execution?: { include_private?: boolean; include_archived?: boolean };
  policy?: {
    vulnerability_alerts?: boolean;
    automated_security_fixes?: boolean;
    private_vulnerability_reporting?: boolean;
    security_and_analysis?: Record<string, "enabled" | "disabled">;
  };
};

type EnvironmentsConfig = {
  version?: number;
  org?: string;
  execution?: { include_private?: boolean; include_archived?: boolean };
  environments?: Array<{ name: string; wait_timer?: number; prevent_self_review?: boolean }>;
};

type DiscussionsConfig = {
  version?: number;
  template?: {
    categories?: Array<{ name: string; description?: string; emoji?: string; is_answerable?: boolean }>;
    labels?: Array<{ name: string; color?: string; description?: string }>;
    initial_discussions?: Array<{ title: string; category: string; labels?: string[]; body: string }>;
  };
};

type TeamsConfig = {
  version?: number;
  org?: string;
  teams?: Array<{
    slug: string;
    title: string;
    description?: string;
    image?: string;
    roles?: string[];
    visible?: boolean;
    notification?: string;
    access?: string;
  }>;
};

function parseJson<T>(raw: string, source: string): T {
  try {
    return JSON.parse(raw) as T;
  } catch (error) {
    throw new Error(`Invalid JSON in ${source}: ${error instanceof Error ? error.message : String(error)}`, {
      cause: error
    });
  }
}

export function loadJsonFile<T>(filePath: string): T {
  return parseJson<T>(fs.readFileSync(filePath, "utf8"), filePath);
}

function ensureVersion(configFile: string, parsed: { version?: number }): void {
  if ((parsed.version ?? 0) !== 1) {
    throw new Error(`Unsupported config version in ${configFile}: ${parsed.version ?? 0}`);
  }
}

export function resolvePathFromRoot(root: string, maybeRelative: string): string {
  if (path.isAbsolute(maybeRelative)) {
    return maybeRelative;
  }
  return path.resolve(root, maybeRelative.replace(/^\.\//, ""));
}

export function toBool(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function parseRepoFull(repoFull: string): { org: string; repo: string } {
  const parts = repoFull.split("/");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    throw new Error(`Invalid repo format '${repoFull}' (expected ORG/REPO)`);
  }
  return { org: parts[0], repo: parts[1] };
}

function runGh(args: string[], opts?: { input?: string; allowError?: boolean }): string {
  const result = spawnSync("gh", args, {
    cwd: REPO_ROOT,
    encoding: "utf8",
    env: process.env,
    input: opts?.input
  });
  if (result.status !== 0 && !opts?.allowError) {
    throw new Error((result.stderr || result.stdout || `gh failed: ${args.join(" ")}`).trim());
  }
  return (result.stdout ?? "").trim();
}

function runGhResult(args: string[], opts?: { input?: string }): { status: number; stdout: string; stderr: string } {
  const result = spawnSync("gh", args, {
    cwd: REPO_ROOT,
    encoding: "utf8",
    env: process.env,
    input: opts?.input
  });
  return {
    status: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? ""
  };
}

function checkGhAuth(): void {
  runGh(["auth", "status"]);
}

function listRepos(org: string): RepoInfo[] {
  const out = runGh(["repo", "list", org, "--limit", "200", "--json", "name,visibility,isArchived"]);
  return parseJson<RepoInfo[]>(out, `gh repo list ${org}`);
}

function validateRequiredTools(): void {
  for (const tool of ["gh", "bash"]) {
    const result = spawnSync("bash", ["-lc", `command -v ${tool}`], { stdio: "ignore" });
    if (result.status !== 0) {
      throw new Error(`Missing required command: ${tool}`);
    }
  }
}

function roleToWeight(role: string): number {
  switch (role) {
    case "all-admin":
    case "admin":
      return 5;
    case "all-maintain":
    case "maintain":
      return 4;
    case "all-write":
    case "write":
    case "all-push":
    case "push":
      return 3;
    case "all-triage":
    case "triage":
      return 2;
    case "all-read":
    case "read":
    case "all-pull":
    case "pull":
      return 1;
    case "all-none":
    case "none":
      return 0;
    default:
      return -1;
  }
}

function weightToPermission(weight: number): "admin" | "maintain" | "push" | "triage" | "pull" {
  switch (weight) {
    case 5:
      return "admin";
    case 4:
      return "maintain";
    case 3:
      return "push";
    case 2:
      return "triage";
    default:
      return "pull";
  }
}

function resolveEffectivePermission(roles: string[]): "admin" | "maintain" | "push" | "triage" | "pull" {
  let maxWeight = 0;
  for (const role of roles) {
    const weight = roleToWeight(role);
    if (weight < 0) {
      throw new Error(`Unknown role token in config: ${role}`);
    }
    maxWeight = Math.max(maxWeight, weight);
  }
  return weightToPermission(maxWeight);
}

function privacyFromVisible(visible: boolean): "closed" | "secret" {
  return visible ? "closed" : "secret";
}

function notificationFromFlag(value: string): "notifications_enabled" | "notifications_disabled" {
  return ["disabled", "disable", "off", "false"].includes(value) ? "notifications_disabled" : "notifications_enabled";
}

function loadPolicyConfig(configFile: string): {
  rulesets: Array<Record<string, unknown>>;
  rulesetName: string;
  repoSettings: Record<string, unknown>;
} {
  const config = loadJsonFile<ManagementConfig>(configFile);
  ensureVersion(configFile, config);

  const repoSettingsCfgPath = resolvePathFromRoot(
    REPO_ROOT,
    config.policy?.repo_settings_config ?? "./config/repo-settings.config.json"
  );
  if (!fs.existsSync(repoSettingsCfgPath)) {
    throw new Error(`Missing file: ${repoSettingsCfgPath}`);
  }
  const repoSettingsCfg = loadJsonFile<RepoSettingsConfig>(repoSettingsCfgPath);
  ensureVersion(repoSettingsCfgPath, repoSettingsCfg);
  if (!repoSettingsCfg.settings || typeof repoSettingsCfg.settings !== "object") {
    throw new Error(`Invalid settings in ${repoSettingsCfgPath}`);
  }

  const rulesetsCfgPath = resolvePathFromRoot(
    REPO_ROOT,
    config.policy?.rulesets_config ?? "./config/rulesets.config.json"
  );
  if (!fs.existsSync(rulesetsCfgPath)) {
    throw new Error(`Missing file: ${rulesetsCfgPath}`);
  }
  const rulesetsCfg = loadJsonFile<RulesetsConfig>(rulesetsCfgPath);
  ensureVersion(rulesetsCfgPath, rulesetsCfg);
  if (!Array.isArray(rulesetsCfg.rulesets) || rulesetsCfg.rulesets.length === 0) {
    throw new Error(`Invalid or empty rulesets in ${rulesetsCfgPath}`);
  }

  return {
    rulesets: rulesetsCfg.rulesets,
    rulesetName: config.policy?.ruleset_name ?? "",
    repoSettings: repoSettingsCfg.settings
  };
}

function resolveRulesetTemplate(
  rawTemplate: string,
  org: string,
  bypassTeamSlug: string,
  reviewerTeamSlug: string
): string {
  let raw = rawTemplate;
  if (raw.includes("__BYPASS_TEAM_ID__")) {
    const bypassId = Number(runGh(["api", `orgs/${org}/teams/${bypassTeamSlug}`, "--jq", ".id"]));
    raw = raw.replaceAll('"__BYPASS_TEAM_ID__"', String(bypassId));
  }
  if (raw.includes("__REQUIRED_REVIEWER_TEAM_ID__")) {
    const reviewerId = Number(runGh(["api", `orgs/${org}/teams/${reviewerTeamSlug}`, "--jq", ".id"]));
    raw = raw.replaceAll('"__REQUIRED_REVIEWER_TEAM_ID__"', String(reviewerId));
  }
  return raw;
}

function upsertRuleset(
  repoFull: string,
  ruleset: Record<string, unknown>,
  opts: { preview: boolean; bypassTeamSlug: string; reviewerTeamSlug: string; forceRulesetName?: string }
): void {
  const { org, repo } = parseRepoFull(repoFull);
  const rawTemplate = JSON.stringify(ruleset);
  const resolved = resolveRulesetTemplate(rawTemplate, org, opts.bypassTeamSlug, opts.reviewerTeamSlug);
  const rulesetJson = parseJson<{ name?: string }>(resolved, "rulesets.config.json");
  const rulesetName = opts.forceRulesetName || rulesetJson.name || "";
  if (!rulesetName) {
    throw new Error("Missing ruleset name in rulesets.config.json");
  }

  const existingRaw = runGh(["api", `repos/${org}/${repo}/rulesets`, "--jq", ".[] | {id,name}"]);
  const existingLines = existingRaw ? existingRaw.split("\n").filter(Boolean) : [];
  let existingId = "";
  for (const line of existingLines) {
    const entry = parseJson<{ id: number; name: string }>(line, "rulesets list entry");
    if (entry.name === rulesetName) {
      existingId = String(entry.id);
      break;
    }
  }

  if (opts.preview) {
    if (existingId) {
      console.log(`[preview] update ruleset: ${rulesetName}`);
    } else {
      console.log(`[preview] create ruleset: ${rulesetName}`);
    }
    return;
  }

  if (existingId) {
    runGh(["api", "-X", "PUT", `repos/${org}/${repo}/rulesets/${existingId}`, "--input", "-"], { input: resolved });
    console.log(`updated: ${rulesetName}`);
  } else {
    runGh(["api", "-X", "POST", `repos/${org}/${repo}/rulesets`, "--input", "-"], { input: resolved });
    console.log(`created: ${rulesetName}`);
  }
}

export function applyRulesetsRepo(
  repoFull: string,
  configFile: string,
  opts: { preview: boolean; bypassTeamSlug: string; reviewerTeamSlug: string; rulesetName?: string }
): void {
  const { rulesets } = loadPolicyConfig(configFile);
  for (const ruleset of rulesets) {
    upsertRuleset(repoFull, ruleset, {
      preview: opts.preview,
      bypassTeamSlug: opts.bypassTeamSlug,
      reviewerTeamSlug: opts.reviewerTeamSlug,
      forceRulesetName: rulesets.length === 1 ? opts.rulesetName : ""
    });
  }
}

export function applyRulesetsOrg(
  org: string,
  configFile: string,
  opts: { preview: boolean; allowPrivate: boolean; maxRepos: number; bypassTeamSlug: string; reviewerTeamSlug: string }
): void {
  const { rulesets } = loadPolicyConfig(configFile);
  const repos = listRepos(org);

  let seen = 0;
  let skipped = 0;
  let applied = 0;
  let failed = 0;

  for (const repo of repos) {
    seen += 1;
    if (opts.maxRepos > 0 && seen > opts.maxRepos) {
      break;
    }
    if (repo.isArchived) {
      console.log(`[skip] ${org}/${repo.name} (archived)`);
      skipped += 1;
      continue;
    }
    if (repo.visibility !== "public" && !opts.allowPrivate) {
      console.log(`[skip] ${org}/${repo.name} (private)`);
      skipped += 1;
      continue;
    }

    let repoOk = true;
    for (const ruleset of rulesets) {
      try {
        upsertRuleset(`${org}/${repo.name}`, ruleset, {
          preview: opts.preview,
          bypassTeamSlug: opts.bypassTeamSlug,
          reviewerTeamSlug: opts.reviewerTeamSlug
        });
      } catch (error) {
        repoOk = false;
        console.error(`[error] ${(error instanceof Error ? error.message : String(error)).trim()}`);
      }
    }

    if (repoOk) {
      applied += 1;
    } else {
      failed += 1;
    }
  }

  console.log(
    `Summary: seen=${seen} applied=${applied} skipped=${skipped} failed=${failed} preview=${opts.preview ? 1 : 0}`
  );
  if (failed > 0) {
    throw new Error("Rulesets org apply finished with failures");
  }
}

function patchRepoSettings(repoFull: string, repoSettings: Record<string, unknown>, preview: boolean): void {
  const { org, repo } = parseRepoFull(repoFull);
  const payload = JSON.stringify(repoSettings);
  if (preview) {
    console.log(`[preview] gh api -X PATCH repos/${org}/${repo} --input repo-settings.config.json`);
    return;
  }
  runGh(["api", "-X", "PATCH", `repos/${org}/${repo}`, "--input", "-"], { input: payload });
}

export function applyOneRepoPolicy(
  repoFull: string,
  opts: {
    configFile: string;
    allowPrivate: boolean;
    repoVisibility?: string;
    repoArchived?: string;
    preview: boolean;
    bypassTeamSlug: string;
    reviewerTeamSlug: string;
  }
): void {
  const { org, repo } = parseRepoFull(repoFull);
  const { repoSettings, rulesets, rulesetName } = loadPolicyConfig(opts.configFile);

  let visibility = opts.repoVisibility ?? "";
  let archived = opts.repoArchived ?? "";
  if (!visibility || !archived) {
    const out = runGh(["api", `repos/${org}/${repo}`, "--jq", "{visibility, archived}"]);
    const parsed = parseJson<{ visibility: string; archived: boolean }>(out, `repos/${org}/${repo}`);
    visibility = parsed.visibility;
    archived = String(parsed.archived);
  }

  if (archived === "true") {
    console.log(`Skipping ${repoFull} (archived).`);
    return;
  }
  if (visibility !== "public" && !opts.allowPrivate) {
    console.log(`Skipping ${repoFull} (visibility=${visibility}, use --allow-private to include).`);
    return;
  }

  console.log(`Applying policy to ${repoFull} (visibility=${visibility})`);
  patchRepoSettings(repoFull, repoSettings, opts.preview);

  let applied = 0;
  for (const ruleset of rulesets) {
    upsertRuleset(repoFull, ruleset, {
      preview: opts.preview,
      bypassTeamSlug: opts.bypassTeamSlug,
      reviewerTeamSlug: opts.reviewerTeamSlug,
      forceRulesetName: rulesets.length === 1 ? rulesetName : ""
    });
    applied += 1;
  }
  console.log(`Applied: settings patched, rulesets applied=${applied}`);
}

export function createRepoCore(
  org: string,
  repo: string,
  opts: {
    visibility: "public" | "private";
    description: string;
    template: string;
    applyPolicy: boolean;
    allowPrivatePolicy: boolean;
    preview: boolean;
    configFile: string;
  }
): void {
  const repoFull = `${org}/${repo}`;

  if (opts.preview) {
    console.log(`[preview] existence check skipped for ${repoFull}`);
    const parts = [`gh repo create ${repoFull}`, `--${opts.visibility}`, "--clone=false"];
    if (opts.description) {
      parts.push(`--description ${JSON.stringify(opts.description)}`);
    }
    if (opts.template) {
      parts.push(`--template ${opts.template}`);
    }
    console.log(`[preview] ${parts.join(" ")}`);
  } else {
    const view = spawnSync("gh", ["repo", "view", repoFull], { cwd: REPO_ROOT, stdio: "ignore" });
    if (view.status === 0) {
      console.log(`Repo exists: ${repoFull}`);
    } else {
      const args = ["repo", "create", repoFull, `--${opts.visibility}`, "--clone=false"];
      if (opts.description) {
        args.push("--description", opts.description);
      }
      if (opts.template) {
        args.push("--template", opts.template);
      }
      runGh(args);
    }
  }

  if (!opts.applyPolicy) {
    console.log("Policy application disabled (--no-apply-policy).");
    return;
  }

  if (opts.preview) {
    console.log(`[preview] apply policy for ${repoFull}`);
    return;
  }

  const visibility = runGh(["api", `repos/${org}/${repo}`, "--jq", ".visibility"]);
  if (!opts.allowPrivatePolicy && visibility !== "public") {
    console.log(`Skipping policy for ${repoFull} (visibility=${visibility}, use --allow-private-policy to include).`);
    return;
  }

  applyOneRepoPolicy(repoFull, {
    configFile: opts.configFile,
    allowPrivate: opts.allowPrivatePolicy,
    preview: false,
    bypassTeamSlug: "aristo-bypass",
    reviewerTeamSlug: "aristobyte-approvers"
  });
}

export function applyOrgPolicy(
  orgs: string[],
  opts: { allowPrivate: boolean; preview: boolean; maxRepos: number; configFile: string }
): void {
  let totalSeen = 0;
  let totalApplied = 0;
  let totalSkipped = 0;
  let totalFailed = 0;

  for (const org of orgs) {
    console.log(`\n=== Org: ${org} ===`);
    const repos = listRepos(org);
    console.log(`Found ${repos.length} repos`);

    let orgSeen = 0;
    let orgApplied = 0;
    let orgSkipped = 0;
    let orgFailed = 0;

    for (const repo of repos) {
      orgSeen += 1;
      if (opts.maxRepos > 0 && orgSeen > opts.maxRepos) {
        break;
      }
      if (repo.isArchived) {
        console.log(`[skip] ${org}/${repo.name} (archived)`);
        orgSkipped += 1;
        continue;
      }
      if (repo.visibility !== "public" && !opts.allowPrivate) {
        console.log(`[skip] ${org}/${repo.name} (private)`);
        orgSkipped += 1;
        continue;
      }

      try {
        applyOneRepoPolicy(`${org}/${repo.name}`, {
          configFile: opts.configFile,
          allowPrivate: opts.allowPrivate,
          repoVisibility: repo.visibility,
          repoArchived: String(repo.isArchived),
          preview: opts.preview,
          bypassTeamSlug: "aristo-bypass",
          reviewerTeamSlug: "aristobyte-approvers"
        });
        orgApplied += 1;
      } catch (error) {
        orgFailed += 1;
        console.error(`[error] Failed: ${org}/${repo.name} ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    totalSeen += orgSeen;
    totalApplied += orgApplied;
    totalSkipped += orgSkipped;
    totalFailed += orgFailed;

    console.log(`Org summary: seen=${orgSeen} applied=${orgApplied} skipped=${orgSkipped} failed=${orgFailed}`);
  }

  console.log(`\n=== Overall summary ===`);
  console.log(`seen=${totalSeen} applied=${totalApplied} skipped=${totalSkipped} failed=${totalFailed}`);
  if (totalFailed > 0) {
    throw new Error("Org policy apply finished with failures");
  }
}

export function applyActionsRepo(repoFull: string, configFile: string, preview: boolean): void {
  const config = loadJsonFile<ActionsConfig>(configFile);
  ensureVersion(configFile, config);

  const mode = config.policy?.allowed_actions_mode ?? "selected";
  if (!(["all", "local_only", "selected"] as const).includes(mode)) {
    throw new Error(`Unsupported allowed_actions_mode: ${mode}`);
  }

  const org = parseRepoFull(repoFull).org;
  const patterns = (config.policy?.patterns_allowed ?? []).map((pattern) => pattern.replaceAll("{ORG}", org));
  if (mode === "selected" && patterns.length === 0) {
    throw new Error("selected mode requires at least one pattern");
  }

  if (preview) {
    console.log(`[preview] set actions policy on ${repoFull}: mode=${mode}`);
    if (mode === "selected") {
      console.log(
        `[preview] selected-actions github_owned_allowed=${toBool(config.policy?.allow_github_owned, true)} verified_allowed=${toBool(config.policy?.allow_verified_creators, false)}`
      );
      for (const pattern of patterns) {
        console.log(`[preview]   pattern: ${pattern}`);
      }
    }
    return;
  }

  const { org: repoOrg, repo } = parseRepoFull(repoFull);
  runGh(["api", "-X", "PUT", `repos/${repoOrg}/${repo}/actions/permissions`, "--input", "-"], {
    input: JSON.stringify({ enabled: true, allowed_actions: mode })
  });

  if (mode === "selected") {
    runGh(["api", "-X", "PUT", `repos/${repoOrg}/${repo}/actions/permissions/selected-actions`, "--input", "-"], {
      input: JSON.stringify({
        github_owned_allowed: toBool(config.policy?.allow_github_owned, true),
        verified_allowed: toBool(config.policy?.allow_verified_creators, false),
        patterns_allowed: patterns
      })
    });
  }

  console.log(`updated actions policy: ${repoFull}`);
}

export function applyActionsOrg(
  org: string,
  configFile: string,
  opts: { preview: boolean; allowPrivate: boolean; includeArchived: boolean; maxRepos: number }
): void {
  const repos = listRepos(org);
  let seen = 0;
  let applied = 0;
  let skipped = 0;
  let failed = 0;

  for (const repo of repos) {
    seen += 1;
    if (opts.maxRepos > 0 && seen > opts.maxRepos) {
      break;
    }

    if (repo.isArchived && !opts.includeArchived) {
      console.log(`[skip] ${org}/${repo.name} (archived)`);
      skipped += 1;
      continue;
    }
    if (repo.visibility !== "public" && !opts.allowPrivate) {
      console.log(`[skip] ${org}/${repo.name} (private)`);
      skipped += 1;
      continue;
    }

    try {
      applyActionsRepo(`${org}/${repo.name}`, configFile, opts.preview);
      applied += 1;
    } catch (error) {
      failed += 1;
      console.error(
        `[error] actions failed for ${org}/${repo.name}: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  console.log(
    `Summary: seen=${seen} applied=${applied} skipped=${skipped} failed=${failed} preview=${opts.preview ? 1 : 0}`
  );
  if (failed > 0) {
    throw new Error("Actions org apply finished with failures");
  }
}

export function applySecurityRepo(repoFull: string, configFile: string, preview: boolean): void {
  const config = loadJsonFile<SecurityConfig>(configFile);
  ensureVersion(configFile, config);
  const { org, repo } = parseRepoFull(repoFull);

  if (preview) {
    console.log(`[preview] apply security policy on ${repoFull}`);
    return;
  }

  const vulnerabilityAlerts = toBool(config.policy?.vulnerability_alerts, true);
  const automatedSecurityFixes = toBool(config.policy?.automated_security_fixes, true);
  const privateVulnReporting = toBool(config.policy?.private_vulnerability_reporting, true);

  runGh(["api", "-X", vulnerabilityAlerts ? "PUT" : "DELETE", `repos/${org}/${repo}/vulnerability-alerts`], {
    allowError: true
  });
  runGh(["api", "-X", automatedSecurityFixes ? "PUT" : "DELETE", `repos/${org}/${repo}/automated-security-fixes`], {
    allowError: true
  });
  runGh(
    ["api", "-X", privateVulnReporting ? "PUT" : "DELETE", `repos/${org}/${repo}/private-vulnerability-reporting`],
    { allowError: true }
  );

  for (const [key, status] of Object.entries(config.policy?.security_and_analysis ?? {})) {
    if (status !== "enabled" && status !== "disabled") {
      throw new Error(`Invalid value for policy.security_and_analysis.${key}: ${status}`);
    }
    const result = runGhResult(["api", "-X", "PATCH", `repos/${org}/${repo}`, "--input", "-"], {
      input: JSON.stringify({ security_and_analysis: { [key]: { status } } })
    });
    if (result.status !== 0) {
      const stderr = result.stderr.trim();
      if (!stderr.includes("Advanced security is always available for public repos.")) {
        console.error(`[warn] security_and_analysis.${key} update failed: ${stderr || result.stdout}`);
      }
    }
  }

  console.log(`updated security policy: ${repoFull}`);
}

export function applySecurityOrg(
  org: string,
  configFile: string,
  opts: { preview: boolean; allowPrivate: boolean; includeArchived: boolean; maxRepos: number }
): void {
  const repos = listRepos(org);
  let seen = 0;
  let applied = 0;
  let skipped = 0;
  let failed = 0;

  for (const repo of repos) {
    seen += 1;
    if (opts.maxRepos > 0 && seen > opts.maxRepos) {
      break;
    }
    if (repo.isArchived && !opts.includeArchived) {
      console.log(`[skip] ${org}/${repo.name} (archived)`);
      skipped += 1;
      continue;
    }
    if (repo.visibility !== "public" && !opts.allowPrivate) {
      console.log(`[skip] ${org}/${repo.name} (private)`);
      skipped += 1;
      continue;
    }

    try {
      applySecurityRepo(`${org}/${repo.name}`, configFile, opts.preview);
      applied += 1;
    } catch (error) {
      failed += 1;
      console.error(
        `[error] security failed for ${org}/${repo.name}: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  console.log(
    `Summary: seen=${seen} applied=${applied} skipped=${skipped} failed=${failed} preview=${opts.preview ? 1 : 0}`
  );
  if (failed > 0) {
    throw new Error("Security org apply finished with failures");
  }
}

export function applyEnvironmentsRepo(repoFull: string, configFile: string, preview: boolean): void {
  const config = loadJsonFile<EnvironmentsConfig>(configFile);
  ensureVersion(configFile, config);
  const { org, repo } = parseRepoFull(repoFull);

  for (const envCfg of config.environments ?? []) {
    if (!envCfg.name) {
      throw new Error("Environment entry has empty name");
    }
    const waitTimer = envCfg.wait_timer ?? 0;
    const preventSelfReview = toBool(envCfg.prevent_self_review, false);

    if (preview) {
      console.log(
        `[preview] upsert env '${envCfg.name}' on ${repoFull} (wait_timer=${waitTimer} prevent_self_review=${preventSelfReview})`
      );
      continue;
    }

    runGh(["api", "-X", "PUT", `repos/${org}/${repo}/environments/${envCfg.name}`, "--input", "-"], {
      input: JSON.stringify({ wait_timer: waitTimer, prevent_self_review: preventSelfReview })
    });
    console.log(`upserted env: ${envCfg.name}`);
  }
}

export function applyEnvironmentsOrg(
  org: string,
  configFile: string,
  opts: { preview: boolean; allowPrivate: boolean; includeArchived: boolean; maxRepos: number }
): void {
  const repos = listRepos(org);
  let seen = 0;
  let applied = 0;
  let skipped = 0;
  let failed = 0;

  for (const repo of repos) {
    seen += 1;
    if (opts.maxRepos > 0 && seen > opts.maxRepos) {
      break;
    }
    if (repo.isArchived && !opts.includeArchived) {
      console.log(`[skip] ${org}/${repo.name} (archived)`);
      skipped += 1;
      continue;
    }
    if (repo.visibility !== "public" && !opts.allowPrivate) {
      console.log(`[skip] ${org}/${repo.name} (private)`);
      skipped += 1;
      continue;
    }

    try {
      applyEnvironmentsRepo(`${org}/${repo.name}`, configFile, opts.preview);
      applied += 1;
    } catch (error) {
      failed += 1;
      console.error(
        `[error] environments failed for ${org}/${repo.name}: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  console.log(
    `Summary: seen=${seen} applied=${applied} skipped=${skipped} failed=${failed} preview=${opts.preview ? 1 : 0}`
  );
  if (failed > 0) {
    throw new Error("Environments org apply finished with failures");
  }
}

function labelIdByName(org: string, repo: string, labelName: string): string {
  const out = runGh([
    "api",
    "graphql",
    "-f",
    "query=query($owner:String!,$name:String!,$label:String!){repository(owner:$owner,name:$name){labels(first:100,query:$label){nodes{id name}}}}",
    "-F",
    `owner=${org}`,
    "-F",
    `name=${repo}`,
    "-F",
    `label=${labelName}`
  ]);
  const parsed = parseJson<{ data?: { repository?: { labels?: { nodes?: Array<{ id: string; name: string }> } } } }>(
    out,
    "label query"
  );
  const found = parsed.data?.repository?.labels?.nodes?.find((n) => n.name === labelName);
  return found?.id ?? "";
}

function ensureLabel(
  org: string,
  repo: string,
  label: { name: string; color?: string; description?: string },
  preview: boolean
): void {
  if (labelIdByName(org, repo, label.name)) {
    console.log(`label exists: ${label.name}`);
    return;
  }
  if (preview) {
    console.log(`[preview] create label: ${label.name}`);
    return;
  }
  runGh([
    "api",
    "-X",
    "POST",
    `repos/${org}/${repo}/labels`,
    "-f",
    `name=${label.name}`,
    "-f",
    `color=${label.color ?? "BFD4F2"}`,
    "-f",
    `description=${label.description ?? ""}`
  ]);
  console.log(`label created: ${label.name}`);
}

function listDiscussionCategories(org: string, repo: string): Array<{ id: number; name: string }> {
  const res = runGhResult(["api", `repos/${org}/${repo}/discussions/categories`]);
  if (res.status !== 0) {
    return [];
  }
  return parseJson<Array<{ id: number; name: string }>>(res.stdout, "categories list");
}

function categoryIdByName(org: string, repo: string, categoryName: string): string {
  const categories = listDiscussionCategories(org, repo);
  const found = categories.find((c) => c.name === categoryName);
  return found ? String(found.id) : "";
}

function ensureCategory(
  org: string,
  repo: string,
  category: { name: string; description?: string; emoji?: string; is_answerable?: boolean },
  preview: boolean
): void {
  if (categoryIdByName(org, repo, category.name)) {
    console.log(`category exists: ${category.name}`);
    return;
  }
  if (preview) {
    console.log(`[preview] create category: ${category.name}`);
    return;
  }
  runGh([
    "api",
    "-X",
    "POST",
    `repos/${org}/${repo}/discussions/categories`,
    "-f",
    `name=${category.name}`,
    "-f",
    `description=${category.description ?? ""}`,
    "-f",
    `emoji=${category.emoji ?? ""}`,
    "-f",
    `is_answerable=${toBool(category.is_answerable, false)}`
  ]);
  console.log(`category created: ${category.name}`);
}

function discussionIdByTitle(org: string, repo: string, title: string): string {
  const res = runGhResult(["api", `repos/${org}/${repo}/discussions`]);
  if (res.status !== 0) {
    return "";
  }
  const parsed = parseJson<Array<{ title: string; node_id?: string }>>(res.stdout, "discussions list");
  const found = parsed.find((d) => d.title === title);
  return found?.node_id ?? "";
}

function createDiscussion(
  org: string,
  repo: string,
  payload: { title: string; body: string; category: string },
  preview: boolean
): string {
  const existing = discussionIdByTitle(org, repo, payload.title);
  if (existing) {
    console.log(`discussion exists: ${payload.title}`);
    return existing;
  }

  const categoryId = categoryIdByName(org, repo, payload.category);
  if (!categoryId) {
    throw new Error(`Missing category for discussion '${payload.title}': ${payload.category}`);
  }

  if (preview) {
    console.log(`[preview] create discussion: ${payload.title}`);
    return "PREVIEW_ID";
  }

  const out = runGh([
    "api",
    "-X",
    "POST",
    `repos/${org}/${repo}/discussions`,
    "-F",
    `category_id=${categoryId}`,
    "-F",
    `title=${payload.title}`,
    "-F",
    `body=${payload.body}`,
    "--jq",
    ".node_id"
  ]);
  return out.trim();
}

function addLabelsToDiscussion(discussionId: string, labelIds: string[], preview: boolean): void {
  if (!discussionId || discussionId === "PREVIEW_ID" || labelIds.length === 0) {
    return;
  }
  if (preview) {
    console.log(`[preview] add ${labelIds.length} labels to discussion`);
    return;
  }

  runGh([
    "api",
    "graphql",
    "-f",
    "query=mutation($labelableId:ID!,$labelIds:[ID!]!){addLabelsToLabelable(input:{labelableId:$labelableId,labelIds:$labelIds}){clientMutationId}}",
    "-F",
    `labelableId=${discussionId}`,
    "-F",
    `labelIds=${JSON.stringify(labelIds)}`
  ]);
}

export function ensureDiscussionsRepo(repoFull: string, configFile: string, preview: boolean): void {
  const config = loadJsonFile<DiscussionsConfig>(configFile);
  ensureVersion(configFile, config);
  const { org, repo } = parseRepoFull(repoFull);

  const repoMetaOut = runGh([
    "api",
    "graphql",
    "-f",
    "query=query($owner:String!,$name:String!){repository(owner:$owner,name:$name){id hasDiscussionsEnabled}}",
    "-F",
    `owner=${org}`,
    "-F",
    `name=${repo}`
  ]);
  const repoMeta = parseJson<{ data?: { repository?: { hasDiscussionsEnabled?: boolean } } }>(
    repoMetaOut,
    "repo discussions metadata"
  );
  const hasDiscussionsEnabled = repoMeta.data?.repository?.hasDiscussionsEnabled === true;

  if (!hasDiscussionsEnabled) {
    if (preview) {
      console.log(`[preview] enable discussions for ${repoFull}`);
    } else {
      runGh(["api", "-X", "PATCH", `repos/${org}/${repo}`, "-f", "has_discussions=true"]);
      console.log(`enabled discussions: ${repoFull}`);
    }
  }

  for (const category of config.template?.categories ?? []) {
    ensureCategory(org, repo, category, preview);
  }
  for (const label of config.template?.labels ?? []) {
    ensureLabel(org, repo, label, preview);
  }

  for (const discussion of config.template?.initial_discussions ?? []) {
    const discussionId = createDiscussion(
      org,
      repo,
      {
        title: discussion.title,
        body: discussion.body,
        category: discussion.category
      },
      preview
    );

    const labelIds: string[] = [];
    for (const labelName of discussion.labels ?? []) {
      const id = labelIdByName(org, repo, labelName);
      if (id) {
        labelIds.push(id);
      }
    }
    addLabelsToDiscussion(discussionId, labelIds, preview);
  }

  console.log(`Done: discussions template initialized for ${repoFull}`);
}

export function ensureDiscussionsOrg(
  org: string,
  configFile: string,
  opts: { allowPrivate: boolean; includeArchived: boolean; maxRepos: number; preview: boolean }
): void {
  const repos = listRepos(org);
  let seen = 0;
  let applied = 0;
  let skipped = 0;
  let failed = 0;

  for (const repo of repos) {
    seen += 1;
    if (opts.maxRepos > 0 && seen > opts.maxRepos) {
      break;
    }
    if (repo.isArchived && !opts.includeArchived) {
      console.log(`[skip] ${org}/${repo.name} (archived)`);
      skipped += 1;
      continue;
    }
    if (repo.visibility !== "public" && !opts.allowPrivate) {
      console.log(`[skip] ${org}/${repo.name} (private)`);
      skipped += 1;
      continue;
    }

    try {
      ensureDiscussionsRepo(`${org}/${repo.name}`, configFile, opts.preview);
      applied += 1;
    } catch (error) {
      failed += 1;
      console.error(
        `[error] discussions failed for ${org}/${repo.name}: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  console.log(
    `Summary: seen=${seen} applied=${applied} skipped=${skipped} failed=${failed} preview=${opts.preview ? 1 : 0}`
  );
  if (failed > 0) {
    throw new Error("Discussions org apply finished with failures");
  }
}

function ensureTeam(
  org: string,
  team: {
    slug: string;
    title: string;
    description: string;
    privacy: "closed" | "secret";
    notification: "notifications_enabled" | "notifications_disabled";
  },
  preview: boolean
): void {
  const exists = runGhResult(["api", `orgs/${org}/teams/${team.slug}`]).status === 0;

  if (exists) {
    if (preview) {
      console.log(`[preview] update team ${org}/${team.slug}`);
    } else {
      runGh([
        "api",
        "-X",
        "PATCH",
        `orgs/${org}/teams/${team.slug}`,
        "-f",
        `name=${team.title}`,
        "-f",
        `description=${team.description}`,
        "-f",
        `privacy=${team.privacy}`,
        "-f",
        `notification_setting=${team.notification}`
      ]);
      console.log(`updated team: ${org}/${team.slug}`);
    }
    return;
  }

  if (preview) {
    console.log(`[preview] create team ${org}/${team.slug}`);
    return;
  }

  runGh([
    "api",
    "-X",
    "POST",
    `orgs/${org}/teams`,
    "-f",
    `name=${team.title}`,
    "-f",
    `description=${team.description}`,
    "-f",
    `privacy=${team.privacy}`,
    "-f",
    `notification_setting=${team.notification}`,
    "-f",
    "permission=pull"
  ]);
  console.log(`created team: ${org}/${team.slug}`);
}

function grantRepoPermission(
  org: string,
  teamSlug: string,
  repoName: string,
  permission: string,
  preview: boolean
): void {
  if (preview) {
    console.log(`[preview] grant ${permission} on ${org}/${repoName} to team ${teamSlug}`);
    return;
  }

  runGh([
    "api",
    "-X",
    "PUT",
    `orgs/${org}/teams/${teamSlug}/repos/${org}/${repoName}`,
    "-f",
    `permission=${permission}`
  ]);
}

export function initTeams(
  org: string,
  configFile: string,
  opts: { preview: boolean; maxRepos: number; includeArchived: boolean }
): void {
  const config = loadJsonFile<TeamsConfig>(configFile);
  ensureVersion(configFile, config);

  for (const teamCfg of config.teams ?? []) {
    if (!teamCfg.slug || !teamCfg.title) {
      throw new Error("Team entry missing slug/title");
    }

    const permission = resolveEffectivePermission(teamCfg.roles ?? []);
    const privacy = privacyFromVisible(toBool(teamCfg.visible, true));
    const notification = notificationFromFlag(teamCfg.notification ?? "enabled");

    console.log(`\n== Team: ${teamCfg.slug}`);
    console.log(`   effective_repo_permission=${permission}`);

    if (teamCfg.image) {
      const imagePath = resolvePathFromRoot(REPO_ROOT, teamCfg.image);
      if (fs.existsSync(imagePath)) {
        console.log(`   image asset found: ${teamCfg.image}`);
      } else {
        console.error(`   image asset missing: ${teamCfg.image}`);
      }
      console.log(
        "   note: GitHub team avatar upload is not available in gh REST flow; set avatar in UI after team creation."
      );
    }

    ensureTeam(
      org,
      {
        slug: teamCfg.slug,
        title: teamCfg.title,
        description: teamCfg.description ?? "",
        privacy,
        notification
      },
      opts.preview
    );

    if ((teamCfg.access ?? "all-repos") !== "all-repos") {
      console.log(`   access=${teamCfg.access} (skipping repo grants)`);
      continue;
    }

    const repos = listRepos(org);
    let count = 0;
    for (const repo of repos) {
      if (repo.isArchived && !opts.includeArchived) {
        continue;
      }
      count += 1;
      if (opts.maxRepos > 0 && count > opts.maxRepos) {
        break;
      }
      grantRepoPermission(org, teamCfg.slug, repo.name, permission, opts.preview);
    }
  }

  console.log("\nDone.");
}

export function removeTeams(org: string, configFile: string, preview: boolean): void {
  const config = loadJsonFile<TeamsConfig>(configFile);
  ensureVersion(configFile, config);

  for (const team of config.teams ?? []) {
    if (!team.slug) {
      continue;
    }

    if (runGhResult(["api", `orgs/${org}/teams/${team.slug}`]).status !== 0) {
      console.log(`[skip] team not found: ${org}/${team.slug}`);
      continue;
    }

    if (preview) {
      console.log(`[preview] delete team: ${org}/${team.slug}`);
      continue;
    }

    runGh(["api", "-X", "DELETE", `orgs/${org}/teams/${team.slug}`]);
    console.log(`deleted team: ${org}/${team.slug}`);
  }

  console.log("Done");
}

export function ensureOrgTeams(org: string, opts: { ownerUser: string; preview: boolean }): void {
  const ensure = (name: string, slug: string, desc: string): void => {
    if (runGhResult(["api", `orgs/${org}/teams/${slug}`]).status === 0) {
      console.log(`Team exists: ${org}/${slug}`);
      return;
    }
    if (opts.preview) {
      console.log(`[preview] create team: ${org}/${name} (${slug})`);
      return;
    }
    runGh([
      "api",
      "-X",
      "POST",
      `orgs/${org}/teams`,
      "-f",
      `name=${name}`,
      "-f",
      `description=${desc}`,
      "-f",
      "privacy=closed",
      "-f",
      "permission=pull"
    ]);
    console.log(`Team created: ${org}/${slug}`);
  };

  ensure("Aristo-Approvers", "aristo-approvers", "Allowed reviewers for protected branch PR approvals");
  ensure("Aristo-Bypass", "aristo-bypass", "Single-user bypass team for emergency ruleset bypass");

  if (opts.preview) {
    console.log(`[preview] ensure member: ${opts.ownerUser} in ${org}/aristo-bypass`);
  } else {
    runGh(["api", "-X", "PUT", `orgs/${org}/teams/aristo-bypass/memberships/${opts.ownerUser}`, "-f", "role=member"]);
    console.log(`Member ensured: ${opts.ownerUser} -> ${org}/aristo-bypass`);
  }

  for (const slug of ["aristo-approvers", "aristo-bypass"]) {
    const res = runGhResult(["api", `orgs/${org}/teams/${slug}`, "--jq", '"team=" + .slug + " id=" + (.id|tostring)']);
    if (res.status === 0) {
      console.log(res.stdout.trim());
    }
  }
}

function walkFiles(root: string, predicate: (entryPath: string) => boolean): string[] {
  const out: string[] = [];
  const stack = [root];
  while (stack.length > 0) {
    const next = stack.pop();
    if (!next) {
      continue;
    }
    const entries = fs.readdirSync(next, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(next, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (predicate(full)) {
        out.push(full);
      }
    }
  }
  return out.sort();
}

function pickConfig(pathOrDefault: string | undefined, fallback: string): string {
  return resolvePathFromRoot(REPO_ROOT, pathOrDefault ?? fallback);
}

export async function runCreateFlow(org: string, repo: string): Promise<void> {
  validateRequiredTools();
  checkGhAuth();

  const appCfgPath = path.resolve(REPO_ROOT, "config/app.config.json");
  const app = loadJsonFile<AppConfig>(appCfgPath);
  ensureVersion(appCfgPath, app);

  const preview = toBool(app.defaults?.preview, false);
  const enableRepoCreate = toBool(app.modules?.repo_create?.enabled, true);
  const enableRulesets = toBool(app.modules?.rulesets?.enabled, true);
  const enableDiscussions = toBool(app.modules?.discussions?.enabled, true);
  const enableActions = toBool(app.modules?.actions?.enabled, true);
  const enableSecurity = toBool(app.modules?.security?.enabled, true);
  const enableEnvironments = toBool(app.modules?.environments?.enabled, true);

  const visibility = app.modules?.repo_create?.visibility === "private" ? "private" : "public";
  const description = app.modules?.repo_create?.description ?? "";
  const template = app.modules?.repo_create?.template ?? "";
  const applyRepoPolicy = toBool(app.modules?.repo_create?.apply_repo_policy, true);

  const rulesetsCfg = pickConfig(app.modules?.rulesets?.config, "./config/management.json");
  const discussionsCfg = pickConfig(app.modules?.discussions?.config, "./config/discussions.config.json");
  const actionsCfg = pickConfig(app.modules?.actions?.config, "./config/actions.config.json");
  const securityCfg = pickConfig(app.modules?.security?.config, "./config/security.config.json");
  const environmentsCfg = pickConfig(app.modules?.environments?.config, "./config/environments.config.json");

  const optionalFailures: string[] = [];

  if (enableRepoCreate) {
    createRepoCore(org, repo, {
      visibility,
      description,
      template,
      applyPolicy: applyRepoPolicy,
      allowPrivatePolicy: true,
      preview,
      configFile: rulesetsCfg
    });
  }

  if (enableRulesets) {
    applyRulesetsRepo(`${org}/${repo}`, rulesetsCfg, {
      preview,
      bypassTeamSlug: "aristo-bypass",
      reviewerTeamSlug: "aristobyte-approvers"
    });
  }

  if (enableDiscussions) {
    try {
      ensureDiscussionsRepo(`${org}/${repo}`, discussionsCfg, preview);
    } catch {
      optionalFailures.push("discussions");
    }
  }

  if (enableActions) {
    try {
      applyActionsRepo(`${org}/${repo}`, actionsCfg, preview);
    } catch {
      optionalFailures.push("actions");
    }
  }

  if (enableSecurity) {
    try {
      applySecurityRepo(`${org}/${repo}`, securityCfg, preview);
    } catch {
      optionalFailures.push("security");
    }
  }

  if (enableEnvironments) {
    try {
      applyEnvironmentsRepo(`${org}/${repo}`, environmentsCfg, preview);
    } catch {
      optionalFailures.push("environments");
    }
  }

  if (optionalFailures.length > 0) {
    console.error(`[warn] create flow completed with optional failures: ${optionalFailures.join(" ")}`);
  } else {
    console.log(`Done: create flow completed for ${org}/${repo}`);
  }
}

export async function runApplyOrgFlow(org: string): Promise<void> {
  validateRequiredTools();
  checkGhAuth();

  const appCfgPath = path.resolve(REPO_ROOT, "config/app.config.json");
  const app = loadJsonFile<AppConfig>(appCfgPath);
  ensureVersion(appCfgPath, app);

  const preview = toBool(app.defaults?.preview, false);
  const allowPrivate = toBool(app.defaults?.allow_private, true);
  const includeArchived = toBool(app.defaults?.include_archived, false);
  const maxRepos = typeof app.defaults?.max_repos === "number" ? app.defaults.max_repos : 0;

  const rulesetsCfg = pickConfig(app.modules?.rulesets?.config, "./config/management.json");
  const discussionsCfg = pickConfig(app.modules?.discussions?.config, "./config/discussions.config.json");
  const actionsCfg = pickConfig(app.modules?.actions?.config, "./config/actions.config.json");
  const securityCfg = pickConfig(app.modules?.security?.config, "./config/security.config.json");
  const environmentsCfg = pickConfig(app.modules?.environments?.config, "./config/environments.config.json");

  if (toBool(app.modules?.rulesets?.enabled, true)) {
    applyRulesetsOrg(org, rulesetsCfg, {
      preview,
      allowPrivate,
      maxRepos,
      bypassTeamSlug: "aristo-bypass",
      reviewerTeamSlug: "aristobyte-approvers"
    });
  }

  if (toBool(app.modules?.actions?.enabled, true)) {
    applyActionsOrg(org, actionsCfg, { preview, allowPrivate, includeArchived, maxRepos });
  }

  if (toBool(app.modules?.security?.enabled, true)) {
    applySecurityOrg(org, securityCfg, { preview, allowPrivate, includeArchived, maxRepos });
  }

  if (toBool(app.modules?.environments?.enabled, true)) {
    applyEnvironmentsOrg(org, environmentsCfg, { preview, allowPrivate, includeArchived, maxRepos });
  }

  if (toBool(app.modules?.discussions?.enabled, true)) {
    ensureDiscussionsOrg(org, discussionsCfg, { preview, allowPrivate, includeArchived, maxRepos });
  }
}

export async function runInitTeamsFlow(org: string): Promise<void> {
  validateRequiredTools();
  checkGhAuth();

  const appCfgPath = path.resolve(REPO_ROOT, "config/app.config.json");
  const app = loadJsonFile<AppConfig>(appCfgPath);
  ensureVersion(appCfgPath, app);

  if (!toBool(app.modules?.teams?.enabled, true)) {
    console.log("Teams module disabled in app config");
    return;
  }

  const teamsCfg = pickConfig(app.modules?.teams?.config, "./config/teams.config.json");
  const preview = toBool(app.defaults?.preview, false);
  const includeArchived = toBool(app.defaults?.include_archived, false);
  const maxRepos = typeof app.defaults?.max_repos === "number" ? app.defaults.max_repos : 0;

  initTeams(org, teamsCfg, { preview, includeArchived, maxRepos });
}

export async function runRemoveTeamsFlow(org: string): Promise<void> {
  validateRequiredTools();
  checkGhAuth();

  const appCfgPath = path.resolve(REPO_ROOT, "config/app.config.json");
  const app = loadJsonFile<AppConfig>(appCfgPath);
  ensureVersion(appCfgPath, app);

  const teamsCfg = pickConfig(app.modules?.teams?.config, "./config/teams.config.json");
  const preview = toBool(app.defaults?.preview, false);
  removeTeams(org, teamsCfg, preview);
}

export function runValidateFlow(): void {
  const configDir = path.resolve(REPO_ROOT, "config");

  console.log("Validating JSON configs...");
  for (const file of walkFiles(configDir, (p) => p.endsWith(".json"))) {
    JSON.parse(fs.readFileSync(file, "utf8"));
    console.log(`  OK ${file}`);
  }

  console.log("\nValidation complete.");
}

export function runManage(command: "validate" | "plan" | "run", configFile: string): void {
  const cfgPath = resolvePathFromRoot(REPO_ROOT, configFile);
  const config = loadJsonFile<ManagementConfig>(cfgPath);
  ensureVersion(cfgPath, config);

  const preview = toBool(config.execution?.preview, true);
  const allowPrivate = toBool(config.execution?.allow_private, false);
  const maxRepos = typeof config.execution?.max_repos_per_org === "number" ? config.execution.max_repos_per_org : 0;
  const createRepos = config.operations?.create_repos ?? [];
  const applyOrgEnabled = toBool(config.operations?.apply_org_policy?.enabled, false);
  const applyOrgOrgs = config.operations?.apply_org_policy?.orgs ?? [];

  if (command === "validate") {
    console.log("Validation OK");
    return;
  }

  const { rulesets } = loadPolicyConfig(cfgPath);
  console.log(`Config: ${cfgPath}`);
  console.log("rulesets:");
  for (const ruleset of rulesets) {
    const name = typeof ruleset.name === "string" ? ruleset.name : "<unnamed>";
    console.log(`- ${name}`);
  }
  console.log(`preview=${preview}`);
  console.log(`allow_private=${allowPrivate}`);
  console.log(`max_repos=${maxRepos}`);

  console.log("\nCreate repos:");
  if (createRepos.length === 0) {
    console.log("- none");
  } else {
    for (const item of createRepos) {
      console.log(
        `- ${item.org}/${item.name} visibility=${item.visibility ?? "public"} apply_policy=${toBool(item.apply_policy, true)}`
      );
    }
  }

  console.log("\nApply org policy:");
  if (!applyOrgEnabled || applyOrgOrgs.length === 0) {
    console.log("- disabled");
  } else {
    for (const org of applyOrgOrgs) {
      console.log(`- ${org}`);
    }
  }

  if (command === "plan") {
    return;
  }

  for (const item of createRepos) {
    createRepoCore(item.org, item.name, {
      visibility: item.visibility === "private" ? "private" : "public",
      description: item.description ?? "",
      template: item.template ?? "",
      applyPolicy: toBool(item.apply_policy, true),
      allowPrivatePolicy: allowPrivate,
      preview,
      configFile: cfgPath
    });
  }

  if (applyOrgEnabled && applyOrgOrgs.length > 0) {
    applyOrgPolicy(applyOrgOrgs, { allowPrivate, preview, maxRepos, configFile: cfgPath });
  }
}
