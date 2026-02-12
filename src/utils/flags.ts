export function parseFlagValue(args: string[], flag: string, fallback = ""): string {
  const idx = args.indexOf(flag);
  if (idx < 0) {
    return fallback;
  }
  const value = args[idx + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

export function hasFlag(args: string[], flag: string): boolean {
  return args.includes(flag);
}

export function parseIntFlag(args: string[], flag: string, fallback = 0): number {
  const raw = parseFlagValue(args, flag, String(fallback));
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${flag} must be non-negative integer`);
  }
  return value;
}

export function parseOrgList(args: string[]): string[] {
  return args.filter((a) => !a.startsWith("--") && a !== "validate" && a !== "plan" && a !== "run");
}
