import { accessSync, constants as fsConstants } from "node:fs";
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { TextDecoder } from "node:util";

const DEFAULT_TIMEOUT_MS = 20_000;
const DEFAULT_CLOSE_GRACE_MS = 1_000;
const DEFAULT_TERM_GRACE_MS = 1_000;
const DEFAULT_KILL_WAIT_MS = 500;
const MAX_STDERR_SUMMARY_LENGTH = 64;
const MAX_STDOUT_LINE_BYTES = 1024 * 1024;
const STDERR_SUMMARY = "[stderr output omitted]";
const APPLICATION_NAMES = ["Codex.app", "ChatGPT.app"];
const RELATIVE_EXECUTABLE_PATHS = [
  "Contents/Resources/codex",
  "Contents/Resources/codex-cli/bin/codex",
  "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
  "Contents/Resources/CodexCLI.app/Contents/MacOS/codex",
];
const SAFE_SPAWN_CODES = new Set(["EACCES", "ENOENT", "ENOEXEC", "EPERM"]);

export class SafeAppServerError extends Error {
  constructor(message) {
    super(message);
    this.name = "SafeAppServerError";
  }
}

export function codexBinCandidates(options = {}) {
  const homeDirectory = options.homeDirectory ?? homedir();
  const environmentValue = Object.hasOwn(options, "environmentValue")
    ? options.environmentValue
    : process.env.CODEX_BIN;
  const applicationRoots = options.applicationRoots ?? ["/Applications", join(homeDirectory, "Applications")];
  const candidates = [];

  if (typeof environmentValue === "string" && environmentValue.trim()) {
    candidates.push(expandCurrentUserTilde(environmentValue, homeDirectory));
  }

  for (const root of applicationRoots) {
    for (const applicationName of APPLICATION_NAMES) {
      for (const relativePath of RELATIVE_EXECUTABLE_PATHS) {
        candidates.push(join(root, applicationName, relativePath));
      }
    }
  }

  return [...new Set(candidates)];
}

export function resolveCodexBin(options = {}) {
  const homeDirectory = options.homeDirectory ?? homedir();
  const environmentValue = Object.hasOwn(options, "environmentValue")
    ? options.environmentValue
    : process.env.CODEX_BIN;

  // Unlike Swift's first-executable candidate list, the CLI treats CODEX_BIN
  // as authoritative. A stale override fails safely instead of launching a
  // different installed app unexpectedly.
  if (typeof environmentValue === "string" && environmentValue.trim()) {
    return expandCurrentUserTilde(environmentValue, homeDirectory);
  }

  const candidates = codexBinCandidates({
    ...options,
    environmentValue: "",
    homeDirectory,
  });
  return candidates.find(isExecutable) ?? null;
}

export class AppServerClient {
  constructor(options = {}) {
    this.codexBin = options.codexBin == null
      ? resolveCodexBin()
      : expandCurrentUserTilde(String(options.codexBin), homedir());
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.closeGraceMs = options.closeGraceMs ?? DEFAULT_CLOSE_GRACE_MS;
    this.termGraceMs = options.termGraceMs ?? DEFAULT_TERM_GRACE_MS;
    this.killWaitMs = options.killWaitMs ?? DEFAULT_KILL_WAIT_MS;
    this.spawnProcess = options.spawnProcess ?? spawn;
    this.env = options.env ?? process.env;
    this.nextId = 1;
    this.pending = new Map();
    this.stderrTail = "";
    this.processFailure = null;
    this.stdoutLineChunks = [];
    this.stdoutLineBytes = 0;
    this.discardingStdoutLine = false;
    this.exited = false;
    this.closing = false;
  }

  async start() {
    if (this.child) {
      if (this.processFailure) {
        throw this.processFailure;
      }
      await this.startPromise;
      if (this.processFailure) {
        throw this.processFailure;
      }
      return;
    }

    if (!this.codexBin) {
      throw new SafeAppServerError("Codex CLI was not found. Set CODEX_BIN to its executable path.");
    }

    let child;
    try {
      child = this.spawnProcess(this.codexBin, ["app-server", "--listen", "stdio://"], {
        stdio: ["pipe", "pipe", "pipe"],
        env: { ...this.env },
      });
    } catch {
      throw new SafeAppServerError("Could not start Codex app-server.");
    }

    this.child = child;
    this.startPromise = new Promise((resolve, reject) => {
      let startupSettled = false;
      const settleStartup = (error) => {
        if (startupSettled) {
          return;
        }
        startupSettled = true;
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      };

      child.once("spawn", () => settleStartup());
      child.on("error", (error) => {
        const failure = safeSpawnError(error);
        this.processFailure ??= failure;
        this.failPending(failure);
        settleStartup(failure);
      });
      child.once("exit", () => {
        this.exited = true;
        const failure = new SafeAppServerError("Codex app-server exited before responding.");
        this.processFailure ??= failure;
        this.failPending(this.processFailure);
        settleStartup(this.processFailure);
      });
      child.once("close", () => {
        this.exited = true;
        const failure = this.processFailure ?? new SafeAppServerError("Codex app-server closed before responding.");
        this.processFailure ??= failure;
        this.failPending(failure);
        settleStartup(failure);
      });

      child.stdin?.on("error", () => {
        const failure = new SafeAppServerError("Could not send a request to Codex app-server.");
        this.processFailure ??= failure;
        this.failPending(this.processFailure);
      });

      if (child.stderr) {
        child.stderr.on("data", (chunk) => {
          if (chunk.length > 0) {
            this.stderrTail = STDERR_SUMMARY.slice(0, MAX_STDERR_SUMMARY_LENGTH);
          }
        });
      }

      if (child.stdout) {
        child.stdout.on("data", (chunk) => this.handleStdoutChunk(chunk));
        child.stdout.once("end", () => this.finishStdout());
        child.stdout.on("error", () => {
          const failure = new SafeAppServerError("Could not read Codex app-server response.");
          this.processFailure ??= failure;
          this.failPending(this.processFailure);
        });
      }
    });

    this.startPromise.catch(() => {});
    await this.startPromise;
  }

  async initialize() {
    await this.request("initialize", {
      clientInfo: {
        name: "codex_usage_status",
        title: "Codex Usage Status",
        version: "0.1.0",
      },
      capabilities: {
        experimentalApi: true,
      },
    });
    this.notify("initialized");
  }

  async readRateLimits() {
    return this.request("account/rateLimits/read");
  }

  async request(method, params) {
    await this.start();
    if (this.processFailure || !this.child?.stdin || this.child.stdin.destroyed) {
      throw this.processFailure ?? new SafeAppServerError("Codex app-server is not available.");
    }

    const id = this.nextId++;
    const pendingKey = String(id);
    const payload = params === undefined ? { method, id } : { method, id, params };
    const line = `${JSON.stringify(payload)}\n`;

    return new Promise((resolve, reject) => {
      const pending = { resolve, reject, timeout: undefined };
      pending.timeout = setTimeout(() => {
        this.rejectPending(pendingKey, new SafeAppServerError("Timed out waiting for Codex app-server."));
      }, this.timeoutMs);
      this.pending.set(pendingKey, pending);

      try {
        this.child.stdin.write(line, (error) => {
          if (error) {
            this.rejectPending(
              pendingKey,
              new SafeAppServerError("Could not send a request to Codex app-server."),
            );
          }
        });
      } catch {
        this.rejectPending(
          pendingKey,
          new SafeAppServerError("Could not send a request to Codex app-server."),
        );
      }
    });
  }

  notify(method, params) {
    if (this.processFailure || !this.child?.stdin || this.child.stdin.destroyed || this.closing) {
      throw this.processFailure ?? new SafeAppServerError("Codex app-server is not available.");
    }

    const payload = params === undefined ? { method } : { method, params };
    try {
      this.child.stdin.write(`${JSON.stringify(payload)}\n`, (error) => {
        if (error) {
          this.processFailure ??= new SafeAppServerError("Could not send a request to Codex app-server.");
          this.failPending(this.processFailure);
        }
      });
    } catch {
      this.processFailure ??= new SafeAppServerError("Could not send a request to Codex app-server.");
      this.failPending(this.processFailure);
      throw this.processFailure;
    }
  }

  handleResponseLine(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }

    if (!message || typeof message !== "object" || Array.isArray(message) || message.id === undefined) {
      return;
    }

    const pendingKey = String(message.id);
    const pending = this.pending.get(pendingKey);
    if (!pending) {
      return;
    }

    if (Object.hasOwn(message, "error") && message.error !== null) {
      this.rejectPending(
        pendingKey,
        new SafeAppServerError("Codex app-server returned an error response."),
      );
      return;
    }

    if (!Object.hasOwn(message, "result")) {
      this.rejectPending(
        pendingKey,
        new SafeAppServerError("Codex app-server returned an invalid response."),
      );
      return;
    }

    this.resolvePending(pendingKey, message.result);
  }

  handleStdoutChunk(chunk) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    let offset = 0;

    while (offset < bytes.length) {
      const newline = bytes.indexOf(0x0a, offset);
      const segmentEnd = newline === -1 ? bytes.length : newline;

      if (!this.discardingStdoutLine) {
        const segment = bytes.subarray(offset, segmentEnd);
        if (this.stdoutLineBytes + segment.length > MAX_STDOUT_LINE_BYTES) {
          this.stdoutLineChunks = [];
          this.stdoutLineBytes = 0;
          this.discardingStdoutLine = true;
          const failure = new SafeAppServerError("Codex app-server returned an oversized response.");
          this.processFailure ??= failure;
          this.failPending(this.processFailure);
        } else if (segment.length > 0) {
          this.stdoutLineChunks.push(segment);
          this.stdoutLineBytes += segment.length;
        }
      }

      if (newline === -1) {
        return;
      }

      if (!this.discardingStdoutLine) {
        this.processStdoutLine();
      }
      this.stdoutLineChunks = [];
      this.stdoutLineBytes = 0;
      this.discardingStdoutLine = false;
      offset = newline + 1;
    }
  }

  finishStdout() {
    if (!this.discardingStdoutLine && this.stdoutLineBytes > 0) {
      this.processStdoutLine();
    }
    this.stdoutLineChunks = [];
    this.stdoutLineBytes = 0;
    this.discardingStdoutLine = false;
  }

  processStdoutLine() {
    const bytes = Buffer.concat(this.stdoutLineChunks, this.stdoutLineBytes);
    const lineBytes = bytes.length > 0 && bytes[bytes.length - 1] === 0x0d
      ? bytes.subarray(0, bytes.length - 1)
      : bytes;
    const line = new TextDecoder("utf-8").decode(lineBytes);
    this.handleResponseLine(line);
  }

  resolvePending(pendingKey, value) {
    const pending = this.pending.get(pendingKey);
    if (!pending) {
      return;
    }
    this.pending.delete(pendingKey);
    clearTimeout(pending.timeout);
    pending.resolve(value);
  }

  rejectPending(pendingKey, error) {
    const pending = this.pending.get(pendingKey);
    if (!pending) {
      return;
    }
    this.pending.delete(pendingKey);
    clearTimeout(pending.timeout);
    pending.reject(error);
  }

  failPending(error) {
    for (const [pendingKey, pending] of this.pending) {
      this.pending.delete(pendingKey);
      clearTimeout(pending.timeout);
      pending.reject(error);
    }
  }

  async close() {
    if (this.closePromise) {
      return this.closePromise;
    }
    const child = this.child;
    if (!child) {
      return;
    }

    this.closing = true;
    this.failPending(new SafeAppServerError("Codex app-server closed before responding."));
    this.closePromise = this.closeChild(child);
    try {
      await this.closePromise;
    } finally {
      if (this.child === child) {
        this.child = undefined;
      }
      this.startPromise = undefined;
      this.closePromise = undefined;
    }
  }

  async closeChild(child) {
    try {
      if (child.stdin && !child.stdin.destroyed && !child.stdin.writableEnded) {
        child.stdin.end();
      }
    } catch {
      // Continue through bounded signal escalation if stdin is already broken.
    }

    let exited = await waitForChildExit(child, this.closeGraceMs);
    if (!exited) {
      safeKill(child, "SIGTERM");
      exited = await waitForChildExit(child, this.termGraceMs);
    }
    if (!exited) {
      safeKill(child, "SIGKILL");
      exited = await waitForChildExit(child, this.killWaitMs);
    }

    if (!exited) {
      child.unref?.();
      child.stdin?.destroy();
      child.stdout?.destroy();
      child.stderr?.destroy();
    }
  }
}

export async function readCodexRateLimits(options = {}) {
  const client = new AppServerClient(options);
  try {
    await client.initialize();
    return await client.readRateLimits();
  } finally {
    await client.close();
  }
}

export function safeErrorMessage(error) {
  return error instanceof SafeAppServerError
    ? error.message
    : "An unexpected error occurred while reading Codex usage.";
}

export function redactSensitive(value) {
  if (typeof value !== "string") {
    return "";
  }

  const redactedAssignments = value.replace(
    /((?:token|cookie|session|authorization|api[_-]?key)[ \t]*[:=][ \t]*)[^\r\n]*/gi,
    "$1[redacted]",
  );
  return redactJwtSegments(redactedAssignments);
}

function expandCurrentUserTilde(value, homeDirectory) {
  const trimmed = value.trim();
  if (trimmed === "~") {
    return homeDirectory;
  }
  if (trimmed.startsWith("~/")) {
    return join(homeDirectory, trimmed.slice(2));
  }
  return trimmed;
}

function isExecutable(path) {
  try {
    accessSync(path, fsConstants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function safeSpawnError(error) {
  const code = SAFE_SPAWN_CODES.has(error?.code) ? ` (${error.code})` : "";
  return new SafeAppServerError(`Could not start Codex app-server${code}.`);
}

function safeKill(child, signal) {
  try {
    child.kill(signal);
  } catch {
    // The process may have exited between the state check and kill.
  }
}

function waitForChildExit(child, timeoutMs) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve(true);
  }

  return new Promise((resolve) => {
    let settled = false;
    const finish = (exited) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timeout);
      child.removeListener("exit", onExit);
      resolve(exited);
    };
    const onExit = () => finish(true);
    const timeout = setTimeout(() => finish(false), timeoutMs);
    child.once("exit", onExit);

    if (child.exitCode !== null || child.signalCode !== null) {
      finish(true);
    }
  });
}

function redactJwtSegments(value) {
  const output = [];
  let index = 0;

  while (index < value.length) {
    if (!isJwtSegmentCharacter(value.charCodeAt(index))) {
      output.push(value[index]);
      index += 1;
      continue;
    }

    const firstStart = index;
    const firstEnd = scanJwtSegment(value, firstStart);
    const secondStart = firstEnd + 1;
    const secondEnd = value.charCodeAt(firstEnd) === 46 ? scanJwtSegment(value, secondStart) : secondStart;
    const thirdStart = secondEnd + 1;
    const thirdEnd = value.charCodeAt(secondEnd) === 46 ? scanJwtSegment(value, thirdStart) : thirdStart;

    if (
      firstEnd - firstStart >= 20 &&
      value.charCodeAt(firstEnd) === 46 &&
      secondEnd - secondStart >= 20 &&
      value.charCodeAt(secondEnd) === 46 &&
      thirdEnd - thirdStart >= 20
    ) {
      output.push("[redacted-jwt]");
      index = thirdEnd;
      continue;
    }

    output.push(value.slice(firstStart, firstEnd));
    index = firstEnd;
  }

  return output.join("");
}

function scanJwtSegment(value, start) {
  let end = start;
  while (isJwtSegmentCharacter(value.charCodeAt(end))) {
    end += 1;
  }
  return end;
}

function isJwtSegmentCharacter(code) {
  return (
    (code >= 48 && code <= 57) ||
    (code >= 65 && code <= 90) ||
    (code >= 97 && code <= 122) ||
    code === 45 ||
    code === 95
  );
}
