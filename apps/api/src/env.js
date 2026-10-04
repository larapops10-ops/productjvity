import { existsSync, readFileSync } from "node:fs";

// Tiny local-only .env reader. Existing system environment values always win.
export function loadLocalEnv(path) {
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^#\s]*))\s*$/);
    if (!match || process.env[match[1]] !== undefined) continue;
    process.env[match[1]] = match[2] ?? match[3] ?? match[4] ?? "";
  }
}
