#!/usr/bin/env node

import { createInterface } from "node:readline";
import { once } from "node:events";

const mode = process.env.FIXTURE_MODE ?? "success";
const secret = "FAKE_SERVER_SECRET_SENTINEL";

if (mode === "early-exit") {
  process.exit(7);
}

if (mode === "ignore-term") {
  process.on("SIGTERM", () => {});
}

let keepAlive;
if (mode === "ignore-term") {
  keepAlive = setInterval(() => {}, 1000);
}

const usage = {
  rateLimits: {
    limitId: "codex",
    primary: {
      usedPercent: 35.5,
      windowDurationMins: 300,
      resetsAt: 2_000_000_000,
      debugToken: secret,
    },
    secondary: {
      usedPercent: 12,
      windowDurationMins: 10080,
      resetsAt: 2_001_000_000,
    },
    diagnosticToken: secret,
  },
};

const input = createInterface({ input: process.stdin });
input.on("close", () => {
  if (mode !== "ignore-term") {
    clearInterval(keepAlive);
    process.exit(0);
  }
});

input.on("line", async (line) => {
  const request = JSON.parse(line);

  if (mode === "silent") {
    return;
  }

  if (request.method === "initialize") {
    const response = `${JSON.stringify({ id: request.id, result: { userAgent: "fixture" } })}\n`;
    process.stdout.write(response);
    return;
  }

  if (request.method !== "account/rateLimits/read") {
    return;
  }

  if (mode === "stderr-flood") {
    const block = "!".repeat(16 * 1024);
    for (let written = 0; written < 2 * 1024 * 1024; written += block.length) {
      if (!process.stderr.write(block)) {
        await once(process.stderr, "drain");
      }
    }
  }

  if (mode === "server-secret") {
    process.stdout.write(
      `${JSON.stringify({ id: request.id, error: { message: `token=${secret}` } })}\n`,
    );
    return;
  }

  if (mode === "exit-after-initialize") {
    process.exit(8);
  }

  if (mode === "oversized-stdout") {
    process.stdout.write(Buffer.alloc(2 * 1024 * 1024, 0x78));
    return;
  }

  const result = mode === "missing-usage"
    ? {
        rateLimits: {
          primary: { windowDurationMins: 300, resetsAt: 2_000_000_000 },
          secondary: { usedPercent: 12, windowDurationMins: 10080, resetsAt: 2_001_000_000 },
        },
      }
    : mode === "fragmented-unicode"
      ? { ...usage, planType: "团队" }
      : usage;
  const response = Buffer.from(`${JSON.stringify({ id: request.id, result })}\n`);
  if (mode === "fragmented-unicode") {
    const splitAt = response.indexOf(Buffer.from("团")) + 1;
    process.stdout.write(response.subarray(0, splitAt));
    setTimeout(() => process.stdout.write(response.subarray(splitAt)), 15);
  } else {
    process.stdout.write(response);
  }
});
