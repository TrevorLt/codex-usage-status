import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { chmod, mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { PassThrough, Writable } from "node:stream";
import test from "node:test";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";

import {
  AppServerClient,
  codexBinCandidates,
  readCodexRateLimits,
  resolveCodexBin,
} from "../src/app-server-client.js";

const fixturePath = fileURLToPath(new URL("./fixtures/fake-codex-app-server.mjs", import.meta.url));
const cliPath = fileURLToPath(new URL("../src/cli.js", import.meta.url));
const fakeSecret = "FAKE_SERVER_SECRET_SENTINEL";

function runCli({ mode = "success", binary = fixturePath, timeoutMs = 4000, args = ["--json"] } = {}) {
  const child = spawn(process.execPath, [cliPath, ...args], {
    env: { ...process.env, CODEX_BIN: binary, FIXTURE_MODE: mode },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const stdout = [];
  const stderr = [];

  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => stdout.push(chunk));
  child.stderr.on("data", (chunk) => stderr.push(chunk));

  return new Promise((resolve, reject) => {
    let timedOut = false;
    const watchdog = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, timeoutMs);

    child.once("error", () => {
      clearTimeout(watchdog);
      reject(new Error("Could not start the CLI test process."));
    });
    child.once("close", (code, signal) => {
      clearTimeout(watchdog);
      resolve({ code, signal, stdout: stdout.join(""), stderr: stderr.join(""), timedOut });
    });
  });
}

test("discovers the Swift-supported app bundle layouts in order", () => {
  const homeDirectory = "/Users/example";
  const layouts = [
    "Contents/Resources/codex",
    "Contents/Resources/codex-cli/bin/codex",
    "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
    "Contents/Resources/CodexCLI.app/Contents/MacOS/codex",
  ];
  const applicationRoots = ["/Applications", join(homeDirectory, "Applications")];
  const expected = [join(homeDirectory, "custom/codex")];

  for (const root of applicationRoots) {
    for (const applicationName of ["Codex.app", "ChatGPT.app"]) {
      for (const layout of layouts) {
        expected.push(join(root, applicationName, layout));
      }
    }
  }

  assert.deepEqual(
    codexBinCandidates({
      environmentValue: " ~/custom/codex ",
      homeDirectory,
    }),
    expected,
  );
  assert.equal(new Set(expected).size, expected.length);
});

test("uses CODEX_BIN as an explicit override and resolves executable app layouts", async () => {
  const override = resolveCodexBin({
    environmentValue: " ~/custom/codex ",
    homeDirectory: "/Users/example",
    applicationRoots: [],
  });
  assert.equal(override, "/Users/example/custom/codex");

  const temporaryDirectory = await mkdtemp(join(tmpdir(), "codex-cli-path-test-"));
  try {
    const applicationRoot = join(temporaryDirectory, "Applications");
    const executable = join(
      applicationRoot,
      "ChatGPT.app",
      "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
    );
    await mkdir(dirname(executable), { recursive: true });
    await writeFile(executable, "#!/bin/sh\nexit 0\n");
    await chmod(executable, 0o755);

    assert.equal(
      resolveCodexBin({
        environmentValue: "",
        homeDirectory: temporaryDirectory,
        applicationRoots: [applicationRoot],
      }),
      executable,
    );
    assert.equal(
      resolveCodexBin({
        environmentValue: "/stale/override/codex",
        homeDirectory: temporaryDirectory,
        applicationRoots: [applicationRoot],
      }),
      "/stale/override/codex",
    );
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("reads usage from an actual local child-process fixture and omits raw fields", async () => {
  const result = await runCli({ mode: "success" });
  assert.equal(result.timedOut, false);
  assert.equal(result.code, 0);

  const usage = JSON.parse(result.stdout);
  assert.equal(usage.fiveHour.remainingPercent, 65);
  assert.equal(usage.weekly.remainingPercent, 88);
  assert.doesNotMatch(result.stdout, new RegExp(fakeSecret));
  assert.doesNotMatch(result.stderr, new RegExp(fakeSecret));
});

test("decodes UTF-8 correctly when a multibyte character crosses stdout chunks", async () => {
  const usage = await readCodexRateLimits({
    codexBin: fixturePath,
    env: { ...process.env, FIXTURE_MODE: "fragmented-unicode" },
    timeoutMs: 1000,
  });

  assert.equal(usage.planType, "团队");
});

test("rejects an oversized unterminated JSONL response with a controlled error", async () => {
  const startedAt = performance.now();
  const result = await runCli({ mode: "oversized-stdout", timeoutMs: 4000 });

  assert.equal(result.timedOut, false);
  assert.equal(result.code, 1);
  assert.ok(performance.now() - startedAt < 3000);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /oversized response/i);
  assert.doesNotMatch(result.stderr, /x{128}/);
});

test("human CLI output shows an unknown partial window as --", async () => {
  const result = await runCli({ mode: "missing-usage", args: [] });
  assert.equal(result.timedOut, false);
  assert.equal(result.code, 0);
  assert.match(result.stdout, /Codex 5h -- 7d 88%/);
  assert.match(result.stdout, /5-hour remaining: --/);
  assert.doesNotMatch(result.stdout, /null%|undefined%/);
});

test("drains large stderr output while keeping only a bounded safe summary", async () => {
  const result = await runCli({ mode: "stderr-flood" });
  assert.equal(result.timedOut, false);
  assert.equal(result.code, 0);
  assert.equal(JSON.parse(result.stdout).fiveHour.remainingPercent, 65);
  assert.doesNotMatch(result.stderr, /!{32}/);
  assert.doesNotMatch(result.stderr, new RegExp(fakeSecret));
});

test("does not print JSON-RPC errors or secret-bearing stdout", async () => {
  const result = await runCli({ mode: "server-secret" });
  assert.equal(result.timedOut, false);
  assert.equal(result.code, 1);
  assert.match(result.stderr, /error response/i);
  assert.doesNotMatch(result.stdout, new RegExp(fakeSecret));
  assert.doesNotMatch(result.stderr, new RegExp(fakeSecret));
  assert.doesNotMatch(result.stderr, /token=/i);
});

test("reports missing executables without an unhandled child-process error", async () => {
  const result = await runCli({
    binary: join(tmpdir(), "codex-usage-status-does-not-exist"),
  });
  assert.equal(result.timedOut, false);
  assert.equal(result.code, 1);
  assert.doesNotMatch(result.stderr, /Unhandled .error. event|throw er;/);
  assert.match(result.stderr, /Could not start Codex app-server|Codex CLI was not found/);
});

test("rejects a pending request promptly when the child exits", async () => {
  const startedAt = performance.now();
  const result = await runCli({ mode: "early-exit", timeoutMs: 3500 });
  const elapsedMs = performance.now() - startedAt;

  assert.equal(result.timedOut, false);
  assert.equal(result.code, 1);
  assert.ok(elapsedMs < 3000, "the request timer should be cleared on child exit");
  assert.match(result.stderr, /exited before responding|Could not send request/i);
});

test("handles an actual child exit during the usage request", async () => {
  const result = await runCli({ mode: "exit-after-initialize", timeoutMs: 3500 });
  assert.equal(result.timedOut, false);
  assert.equal(result.code, 1);
  assert.match(result.stderr, /exited before responding|Could not send request/i);
  assert.doesNotMatch(result.stderr, new RegExp(fakeSecret));
});

test("handles stdin write errors without surfacing the underlying error text", async () => {
  let child;
  const client = new AppServerClient({
    codexBin: "fixture-codex",
    timeoutMs: 1000,
    closeGraceMs: 20,
    termGraceMs: 20,
    killWaitMs: 100,
    spawnProcess: () => {
      child = new EventEmitter();
      child.stdin = new Writable({
        write(_chunk, _encoding, callback) {
          setImmediate(() => callback(new Error(`token=${fakeSecret}`)));
        },
      });
      child.stdout = new PassThrough();
      child.stderr = new PassThrough();
      child.exitCode = null;
      child.signalCode = null;
      child.kill = (signal) => {
        child.signalCode = signal;
        child.emit("exit", null, signal);
        return true;
      };
      child.unref = () => {};
      setImmediate(() => child.emit("spawn"));
      return child;
    },
  });

  await assert.rejects(
    client.request("initialize"),
    (error) => error.message === "Could not send a request to Codex app-server.",
  );
  await client.close();
  assert.equal(child.signalCode, "SIGTERM");
});

test("maps a silent child timeout to a safe bounded diagnostic", async () => {
  await assert.rejects(
    readCodexRateLimits({
      codexBin: fixturePath,
      env: { ...process.env, FIXTURE_MODE: "silent" },
      timeoutMs: 50,
      closeGraceMs: 100,
      termGraceMs: 100,
      killWaitMs: 250,
    }),
    (error) => error.message === "Timed out waiting for Codex app-server.",
  );
});

test("escalates bounded child shutdown from TERM to KILL", async () => {
  const client = new AppServerClient({
    codexBin: fixturePath,
    env: { ...process.env, FIXTURE_MODE: "ignore-term" },
    timeoutMs: 1000,
    closeGraceMs: 40,
    termGraceMs: 40,
    killWaitMs: 500,
  });

  await client.initialize();
  client.notify("initialized");
  await client.readRateLimits();

  const child = client.child;
  const startedAt = performance.now();
  await client.close();

  assert.equal(child.signalCode, "SIGKILL");
  assert.ok(performance.now() - startedAt < 1500);
});
