import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const [executable, fixture, scratchDirectory] = process.argv.slice(2);
if (!executable || !fixture || !scratchDirectory) {
  throw new Error('usage: node run.mjs <harness> <fake-server> <scratch-directory>');
}

async function run(mode, timeoutMilliseconds = 8_000) {
  const pidFile = join(scratchDirectory, `${mode}.pid`);
  const grandchildPidFile = join(scratchDirectory, `${mode}.grandchild.pid`);
  rmSync(pidFile, { force: true });
  rmSync(grandchildPidFile, { force: true });
  const startedAt = performance.now();
  const child = spawn(executable, ['fetch'], {
    env: {
      ...process.env,
      CODEX_BIN: fixture,
      NATIVE_FAULT_MODE: mode,
      NATIVE_FAULT_PID_FILE: pidFile,
      NATIVE_FAULT_GRANDCHILD_PID_FILE: grandchildPidFile
    },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  let stdout = '';
  let stderr = '';
  let timedOut = false;
  child.stdout.on('data', chunk => { stdout = (stdout + chunk.toString()).slice(-8_000); });
  child.stderr.on('data', chunk => { stderr = (stderr + chunk.toString()).slice(-8_000); });

  const result = await new Promise(resolve => {
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, timeoutMilliseconds);
    child.once('error', error => {
      clearTimeout(timer);
      resolve({ error: String(error) });
    });
    child.once('close', (code, signal) => {
      clearTimeout(timer);
      resolve({ code, signal });
    });
  });
  const fetchSeconds = Number(((performance.now() - startedAt) / 1000).toFixed(3));

  let pid;
  try {
    pid = Number(readFileSync(pidFile, 'utf8').trim());
  } catch {}
  let grandchildPid;
  try {
    grandchildPid = Number(readFileSync(grandchildPidFile, 'utf8').trim());
  } catch {}

  const processExited = pid ? await waitForExit(pid, 2_000) : false;
  const grandchildExited = grandchildPid ? await waitForExit(grandchildPid, 2_500) : false;
  return {
    ...result,
    stdout: stdout.trim(),
    stderr: stderr.trim(),
    timedOut,
    seconds: Number(((performance.now() - startedAt) / 1000).toFixed(3)),
    fetchSeconds,
    processExited,
    pid,
    grandchildExited,
    grandchildPid
  };
}

async function waitForExit(pid, timeoutMilliseconds) {
  const deadline = Date.now() + timeoutMilliseconds;
  while (Date.now() < deadline) {
    try {
      process.kill(pid, 0);
    } catch (error) {
      if (error.code === 'ESRCH') return true;
      throw error;
    }
    await delay(25);
  }
  try {
    process.kill(pid, 0);
    return false;
  } catch (error) {
    if (error.code === 'ESRCH') return true;
    throw error;
  }
}

const cases = [
  {
    mode: 'early-exit',
    valid: result => result.code === 1 && result.stdout.includes('status 7') && result.seconds < 3
  },
  {
    mode: 'early-exit-output',
    valid: result => result.code === 0 && result.stdout.includes('5h 65% 7d 88%') && result.seconds < 2
  },
  {
    mode: 'success',
    valid: result => result.code === 0 && result.stdout.includes('5h 65% 7d 88%')
  },
  {
    mode: 'stderr-flood',
    valid: result => result.code === 0 && result.stdout.includes('5h 65% 7d 88%') && result.seconds < 5
  },
  {
    mode: 'unicode-fragmented',
    valid: result => result.code === 0 && result.stdout.includes('5h 65% 7d 88%') && result.seconds < 5
  },
  {
    mode: 'null-result',
    valid: result => result.code === 1 && result.stdout.includes('unsupported usage response') && !result.signal
  },
  {
    mode: 'scalar-result',
    valid: result => result.code === 1 && result.stdout.includes('unsupported usage response') && !result.signal
  },
  {
    mode: 'stderr-auth-exit',
    valid: result => result.code === 1 && result.stdout.includes('not signed in') &&
      !result.stdout.includes('SYNTHETIC_SECRET_SENTINEL')
  },
  {
    mode: 'stdout-overflow',
    valid: result => result.code === 1 && result.stdout.includes('unsupported usage response') && result.seconds < 6
  },
  {
    mode: 'ignore-term',
    valid: result => result.code === 0 && result.stdout.includes('5h 65% 7d 88%') && result.seconds < 5
  },
  {
    mode: 'inherited-fd',
    valid: result => result.code === 0 && result.stdout.includes('5h 65% 7d 88%') &&
      result.fetchSeconds < 1 && Boolean(result.grandchildPid) && result.grandchildExited
  },
  {
    mode: 'hang',
    timeoutMilliseconds: 25_000,
    valid: result => result.code === 1 && result.stdout.includes('20 seconds') &&
      result.seconds < 23.5 && !result.timedOut
  }
];

let failed = false;
for (const test of cases) {
  const result = await run(test.mode, test.timeoutMilliseconds);
  const descendantsExited = result.processExited && (!result.grandchildPid || result.grandchildExited);
  const pass = test.valid(result) && descendantsExited;
  console.log(`${pass ? 'PASS' : 'FAIL'} ${test.mode}: ${result.seconds}s exit=${result.code} signal=${result.signal || '-'} child-exited=${result.processExited} inherited-child-exited=${result.grandchildPid ? result.grandchildExited : 'n/a'}`);
  if (!pass) {
    console.error(JSON.stringify({ mode: test.mode, ...result }, null, 2));
    failed = true;
  }
}

if (failed) {
  console.error(`NATIVE FAULTS FAIL (${cases.length} process scenarios)`);
  process.exitCode = 1;
} else {
  const requestFile = join(scratchDirectory, 'reset-requests.jsonl');
  async function consume(key, creditID, mode) {
    const args = ['consume', key];
    if (creditID !== undefined) args.push(creditID);
    const child = spawn(executable, args, {
      env: { ...process.env, CODEX_BIN: fixture, NATIVE_FAULT_MODE: mode, NATIVE_RESET_REQUEST_FILE: requestFile },
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let output = '';
    child.stdout.on('data', chunk => { output += chunk.toString(); });
    child.stderr.resume();
    const code = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error('consume fixture timed out')); }, 5_000);
      child.once('error', error => { clearTimeout(timer); reject(error); });
      child.once('close', code => { clearTimeout(timer); resolve(code); });
    });
    return { code, output };
  }
  rmSync(requestFile, { force: true });
  const creditID = 'credit-"\\\n模型';
  const key = 'same-reset-request';
  assert.equal((await consume(key, creditID, 'reset-lost-response')).code, 1);
  const retry = await consume(key, creditID, 'reset-lost-response');
  assert.equal(retry.code, 0);
  assert.match(retry.output, /CONSUME SUCCESS: alreadyRedeemed/);
  const requests = readFileSync(requestFile, 'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(requests.length, 2);
  assert.deepEqual(requests[0], { method: 'account/rateLimitResetCredit/consume', id: 2, params: { creditId: creditID, idempotencyKey: key } });
  assert.deepEqual(requests[1], requests[0]);
  rmSync(requestFile);
  for (const credit of [undefined, '', '   ']) {
    assert.equal((await consume('missing-credit', credit, 'success')).code, 1);
    assert.equal(existsSync(requestFile), false, 'missing credit IDs must never reach the server');
  }
  console.log('RESET WIRE PASS: exact method/params, escaped credit ID, lost-response retry, and local rejection of missing credit IDs');
  console.log(`NATIVE FAULTS PASS (${cases.length} process scenarios)`);
}
