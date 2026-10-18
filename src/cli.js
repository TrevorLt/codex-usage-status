#!/usr/bin/env node
import { readCodexRateLimits, safeErrorMessage } from "./app-server-client.js";
import { formatTextStatus, normalizeUsage } from "./usage-format.js";

const args = new Set(process.argv.slice(2));

try {
  const raw = await readCodexRateLimits();
  const usage = normalizeUsage(raw);

  if (args.has("--json")) {
    console.log(JSON.stringify(usage, null, 2));
  } else {
    console.log(formatTextStatus(usage));
  }
} catch (error) {
  console.error(`Unable to read Codex usage safely: ${safeErrorMessage(error)}`);
  process.exitCode = 1;
}
