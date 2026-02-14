import chalk from "chalk";

export type LogMode = "color" | "plain";

function isSeparator(line: string): boolean {
  return /^\s*=+>/.test(line) || /^\s*-{3,}\s*$/.test(line);
}

export function styleLine(input: string, mode: LogMode): string {
  if (mode === "plain") {
    return input;
  }

  const line = input.trimEnd();

  if (!line) {
    return input;
  }

  if (isSeparator(line)) {
    return chalk.cyanBright(line);
  }

  if (/^Summary:/i.test(line)) {
    return chalk.bold.magenta(line);
  }

  if (/^\[error\]/i.test(line) || /^error:/i.test(line)) {
    return chalk.bold.red(line);
  }

  if (/^\[warn\]/i.test(line) || /^warn:/i.test(line)) {
    return chalk.yellowBright(line);
  }

  if (/^\[skip\]/i.test(line)) {
    return chalk.hex("#FFB020")(line);
  }

  if (/^Checking GitHub auth/i.test(line)) {
    return chalk.cyan(line);
  }

  if (/^==>\s+/i.test(line)) {
    return chalk.bold.cyanBright(line);
  }

  if (/^(created|updated|upserted|deleted|removed):/i.test(line) || /^Done\.?$/i.test(line)) {
    return chalk.greenBright(line);
  }

  if (/^Validation (OK|complete)/i.test(line) || /^\s+OK\s+/i.test(line)) {
    return chalk.green(line);
  }

  return line;
}

export function info(msg: string, mode: LogMode): string {
  return mode === "plain" ? msg : chalk.cyan(msg);
}

export function header(msg: string, mode: LogMode): string {
  return mode === "plain" ? msg : chalk.bold.white.bgBlue(` ${msg} `);
}

export function success(msg: string, mode: LogMode): string {
  return mode === "plain" ? msg : chalk.bold.green(msg);
}
