import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

test('local startup unloads the login job, stops only known copies, verifies the new path, and restores failures', async () => {
  const root = await mkdtemp(join(tmpdir(), 'codex-launch-lifecycle-'));
  const log = join(root, 'commands.log');
  const processes = join(root, 'processes');
  const agent = join(root, 'agent');
  const plist = join(root, 'login.plist');
  const executable = join(root, 'dist/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus');
  const installed = '/Applications/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus';
  try {
    await mkdir(join(root, 'scripts'));
    await mkdir(join(root, 'bin'));
    await copyFile(new URL('../scripts/run-macos-app.sh', import.meta.url), join(root, 'scripts/run-macos-app.sh'));
    await writeFile(plist, 'preserve login settings');
    const shellSetup = join(root, 'shell-setup');
    await writeFile(shellSetup, 'kill() { mock-kill "$@"; }\n');
    const commands = {
      uname: 'echo arm64', sysctl: 'echo 1', lipo: 'exit 0', sleep: 'exit 0',
      pkill: 'echo UNSAFE-pkill >> "$TEST_LOG"; exit 1',
      ps: `case "$1" in
        -axww) cat "$TEST_PROCESSES" ;;
        -p) awk -v pid="$2" '$1 == pid { print $2; found=1 } END { exit !found }' "$TEST_PROCESSES" ;;
        *) exit 1 ;;
      esac`,
      launchctl: `case "$1" in
        list) if test "$(cat "$TEST_AGENT")" = loaded; then echo '101 0 dev.local.CodexUsageStatus'; fi ;;
        print) printf 'path = %s\\n' "$TEST_PLIST" ;;
        bootout)
          echo bootout >> "$TEST_LOG"
          test "$TEST_MODE" != bootout-failure || exit 1
          echo unloaded > "$TEST_AGENT"
          awk '$1 != 101' "$TEST_PROCESSES" > "$TEST_PROCESSES.tmp"
          mv "$TEST_PROCESSES.tmp" "$TEST_PROCESSES" ;;
        bootstrap)
          echo bootstrap >> "$TEST_LOG"
          echo loaded > "$TEST_AGENT" ;;
        *) exit 1 ;;
      esac`,
      'mock-kill': `echo "kill $2" >> "$TEST_LOG"
        if test "$TEST_MODE" != stuck-process; then
          awk -v pid="$2" '$1 != pid' "$TEST_PROCESSES" > "$TEST_PROCESSES.tmp"
          mv "$TEST_PROCESSES.tmp" "$TEST_PROCESSES"
        fi`,
      open: `echo open >> "$TEST_LOG"
        test "$TEST_MODE" != open-failure || exit 1
        if test "$TEST_MODE" = wrong-copy; then
          echo '401 S /Applications/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus' >> "$TEST_PROCESSES"
        else
          printf '400 S %s\\n' "$TEST_EXECUTABLE" >> "$TEST_PROCESSES"
        fi`
    };
    for (const [name, body] of Object.entries(commands)) {
      const path = join(root, 'bin', name);
      await writeFile(path, `#!/bin/sh\n${body}\n`);
      await chmod(path, 0o755);
    }
    for (const [mode, expected] of [
      ['success', ['bootout', 'kill 303', 'open']],
      ['bootout-failure', ['bootout']],
      ['stuck-process', ['bootout', 'kill 303', 'bootstrap']],
      ['open-failure', ['bootout', 'kill 303', 'open', 'bootstrap']],
      ['wrong-copy', ['bootout', 'kill 303', 'open', 'bootstrap']]
    ]) {
      await writeFile(log, '');
      await writeFile(agent, 'loaded');
      await writeFile(processes, `101 S ${installed}\n202 S /unrelated/CodexUsageStatus\n303 S ${executable}\n-1 S ${executable}\n0 S ${executable}\n`);
      const result = spawnSync('/bin/bash', [join(root, 'scripts/run-macos-app.sh')], {
        encoding: 'utf8', timeout: 10_000,
        env: { ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`,
          BASH_ENV: shellSetup, TEST_MODE: mode, TEST_LOG: log, TEST_PROCESSES: processes,
          TEST_AGENT: agent, TEST_PLIST: plist, TEST_EXECUTABLE: executable }
      });
      assert.equal(result.error, undefined);
      assert.equal(result.status, mode === 'success' ? 0 : 1, result.stderr);
      assert.deepEqual((await readFile(log, 'utf8')).trim().split('\n'), expected, mode);
      assert.match(await readFile(processes, 'utf8'), /202 S \/unrelated\/CodexUsageStatus/);
      assert.equal(await readFile(plist, 'utf8'), 'preserve login settings');
      assert.equal((await readFile(agent, 'utf8')).trim(), mode === 'success' ? 'unloaded' : 'loaded');
      if (mode === 'success') assert.match(result.stdout, /Started .*PID 400/);
      else assert.doesNotMatch(result.stdout, /Started /);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
