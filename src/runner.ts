import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { header, info, LogMode, styleLine, success } from "./log.js";

const THIS_FILE = fileURLToPath(import.meta.url);
const REPO_ROOT = path.resolve(path.dirname(THIS_FILE), "..");

type RunOptions = {
  script: string;
  args?: string[];
  mode: LogMode;
};

function scriptPath(relativePath: string): string {
  if (!relativePath.startsWith("scripts/") || !relativePath.endsWith(".sh") || relativePath.includes("..")) {
    throw new Error(`Unsafe script path: ${relativePath}`);
  }
  return path.resolve(REPO_ROOT, relativePath);
}

function pumpStream(stream: NodeJS.ReadableStream, writer: (line: string) => void, mode: LogMode): Promise<void> {
  return new Promise((resolve) => {
    let buffer = "";

    stream.on("data", (chunk) => {
      buffer += chunk.toString();

      let idx = buffer.indexOf("\n");
      while (idx >= 0) {
        const line = buffer.slice(0, idx);
        writer(styleLine(line, mode));
        buffer = buffer.slice(idx + 1);
        idx = buffer.indexOf("\n");
      }
    });

    stream.on("end", () => {
      if (buffer.length > 0) {
        writer(styleLine(buffer, mode));
      }
      resolve();
    });
  });
}

export async function runScript({ script, args = [], mode }: RunOptions): Promise<void> {
  const absoluteScript = scriptPath(script);
  const command = `bash ${absoluteScript} ${args.join(" ")}`.trim();

  console.log(header(`Running ${script}`, mode));
  console.log(info(`command: ${command}`, mode));

  const child = spawn("bash", [absoluteScript, ...args], {
    cwd: REPO_ROOT,
    stdio: ["inherit", "pipe", "pipe"],
    env: process.env
  });

  const [outDone, errDone] = await Promise.all([
    child.stdout ? pumpStream(child.stdout, (line) => process.stdout.write(`${line}\n`), mode) : Promise.resolve(),
    child.stderr ? pumpStream(child.stderr, (line) => process.stderr.write(`${line}\n`), mode) : Promise.resolve()
  ]);

  void outDone;
  void errDone;

  const code = await new Promise<number>((resolve, reject) => {
    child.on("error", reject);
    child.on("close", (c) => resolve(c ?? 1));
  });

  if (code !== 0) {
    throw new Error(`Script failed with exit code ${code}: ${script}`);
  }

  console.log(success(`Finished ${script}`, mode));
}
