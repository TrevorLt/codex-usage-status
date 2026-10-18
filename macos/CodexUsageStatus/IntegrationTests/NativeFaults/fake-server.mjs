#!/usr/bin/env node
import { createInterface } from 'node:readline';
import { spawn } from 'node:child_process';
import { appendFileSync } from 'node:fs';

const mode = process.env.NATIVE_FAULT_MODE || 'success';
const pidFile = process.env.NATIVE_FAULT_PID_FILE;
const grandchildPidFile = process.env.NATIVE_FAULT_GRANDCHILD_PID_FILE;
if (pidFile) appendFileSync(pidFile, `${process.pid}\n`);

if (mode === 'early-exit') process.exit(7);
if (mode === 'stderr-auth-exit') {
  await new Promise(resolve => process.stderr.write('authentication failed; token=SYNTHETIC_SECRET_SENTINEL\n', resolve));
  process.exit(9);
}

const result = {
  rateLimits: {
    limitId: 'codex',
    primary: { usedPercent: 35.1, windowDurationMins: 300, resetsAt: 2_000_000_000 },
    secondary: { usedPercent: 12, windowDurationMins: 10_080, resetsAt: 2_001_000_000 },
    planType: mode === 'unicode-fragmented' ? '模型' : 'plus'
  }
};
const hold = setInterval(() => {}, 1000);
if (mode === 'ignore-term') process.on('SIGTERM', () => {});

const input = createInterface({ input: process.stdin });
input.on('close', () => {
  if (mode !== 'ignore-term') {
    clearInterval(hold);
    process.exit(0);
  }
});

function write(stream, data) {
  return new Promise((resolve, reject) => {
    stream.write(data, error => error ? reject(error) : resolve());
  });
}

const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

function startInheritedDescriptorChild() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [
      '-e',
      'process.on("SIGTERM", () => {}); process.send("ready"); setTimeout(() => process.exit(0), 1200)'
    ], {
      stdio: ['inherit', 'inherit', 'inherit', 'ipc']
    });
    child.once('error', reject);
    child.once('message', message => {
      if (message !== 'ready') {
        reject(new Error('inherited descriptor fixture did not become ready'));
        return;
      }
      if (grandchildPidFile) appendFileSync(grandchildPidFile, `${child.pid}\n`);
      resolve();
    });
  });
}

async function writeUnicodeFragmented(line) {
  const bytes = Buffer.from(line);
  const marker = Buffer.from('模型');
  const markerOffset = bytes.indexOf(marker);
  if (markerOffset < 0) throw new Error('unicode fixture marker missing');

  await write(process.stdout, bytes.subarray(0, markerOffset));
  for (const byte of marker) {
    await write(process.stdout, Buffer.from([byte]));
    await wait(15);
  }
  await write(process.stdout, bytes.subarray(markerOffset + marker.length));
}

input.on('line', line => {
  let request;
  try {
    request = JSON.parse(line);
  } catch {
    return;
  }
  if (request.method !== 'account/rateLimits/read') return;

  void (async () => {
    if (mode === 'hang') return;

    if (mode === 'inherited-fd') await startInheritedDescriptorChild();

    if (mode === 'stderr-flood') {
      await write(process.stderr, Buffer.alloc(2 * 1024 * 1024, 0x78));
    }

    if (mode === 'stdout-overflow') {
      process.stdout.write('{"id":2,"result":{"padding":"' + 'x'.repeat(2 * 1024 * 1024));
      return;
    }

    let rpcResult = result;
    if (mode === 'null-result') rpcResult = null;
    if (mode === 'scalar-result') rpcResult = 42;
    const line = `${JSON.stringify({ id: 2, result: rpcResult })}\n`;

    if (mode === 'unicode-fragmented') {
      await writeUnicodeFragmented(line);
    } else {
      await write(process.stdout, line);
    }

    if (mode === 'early-exit-output') process.exit(0);
  })().catch(() => process.exit(11));
});
