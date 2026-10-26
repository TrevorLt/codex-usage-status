import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

test('local startup uses the hardware architecture before stopping or opening an app', async () => {
  const root = await mkdtemp(join(tmpdir(), 'codex-native-launch-test-'));
  const log = join(root, 'commands.log');
  const started = join(root, 'started');
  const executable = join(root, 'dist/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus');
  try {
    await mkdir(join(root, 'scripts'));
    await mkdir(join(root, 'bin'));
    await mkdir(join(root, 'dist/Codex Usage Status.app/Contents/MacOS'), { recursive: true });
    await copyFile(new URL('../scripts/run-macos-app.sh', import.meta.url), join(root, 'scripts/run-macos-app.sh'));
    const commands = {
      'bin/uname': 'echo "$TEST_PROCESS_ARCH"',
      'bin/sysctl': 'echo "$TEST_ARM_HARDWARE"',
      'bin/lipo': 'test "$1" = -verify_arch && grep -qw "$2" "$3"',
      'bin/pkill': 'echo UNSAFE-pkill >> "$TEST_LOG"; exit 1',
      'bin/launchctl': 'exit 0',
      'bin/ps': 'if test -f "$TEST_STARTED"; then printf "999 S %s\\n" "$TEST_EXECUTABLE"; fi',
      'bin/open': 'echo open >> "$TEST_LOG"; touch "$TEST_STARTED"',
      'scripts/build-macos-app.sh': 'echo "build $BUILD_ARCH" >> "$TEST_LOG"\nprintf "%s" "${TEST_REBUILT_ARCH:-$BUILD_ARCH}" > "$TEST_EXECUTABLE"'
    };
    for (const [name, body] of Object.entries(commands)) {
      const path = join(root, name);
      await writeFile(path, `#!/bin/sh\n${body}\n`);
      await chmod(path, 0o755);
    }
    for (const [processArch, armHardware, binaryArch, rebuiltArch, expected] of [
      ['arm64', '1', 'x86_64', '', ['build arm64', 'open']],
      ['x86_64', '1', 'x86_64', '', ['build arm64', 'open']],
      ['arm64', '1', 'arm64', '', ['open']],
      ['arm64', '1', 'arm64 x86_64', '', ['open']],
      ['x86_64', '0', 'x86_64', '', ['open']],
      ['arm64', '1', 'x86_64', 'x86_64', ['build arm64']]
    ]) {
      await writeFile(executable, binaryArch);
      await writeFile(log, '');
      await rm(started, { force: true });
      const result = spawnSync('/bin/bash', [join(root, 'scripts/run-macos-app.sh')], {
        encoding: 'utf8',
        env: {
          ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`, BUILD_ARCH: 'x86_64',
          TEST_PROCESS_ARCH: processArch, TEST_ARM_HARDWARE: armHardware,
          TEST_REBUILT_ARCH: rebuiltArch, TEST_LOG: log, TEST_EXECUTABLE: executable, TEST_STARTED: started
        }
      });
      assert.equal(result.error, undefined);
      assert.equal(result.status, rebuiltArch ? 1 : 0, result.stderr);
      const actual = (await readFile(log, 'utf8')).trim().split('\n');
      assert.deepEqual(actual, expected, `${processArch} process, ARM=${armHardware}, binary=${binaryArch}`);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('dual-architecture packaging clears a stale BUILD_ARCH before restoring the native app', async () => {
  const root = await mkdtemp(join(tmpdir(), 'codex-package-native-test-'));
  const log = join(root, 'builds.log');
  try {
    await mkdir(join(root, 'scripts'));
    await mkdir(join(root, 'bin'));
    await mkdir(join(root, 'dist'));
    await copyFile(new URL('../scripts/package-all-macos.sh', import.meta.url), join(root, 'scripts/package-all-macos.sh'));
    for (const [name, body] of Object.entries({
      'scripts/build-macos-app.sh': 'echo "${BUILD_ARCH:-native}" >> "$TEST_LOG"',
      'scripts/package-dmg.sh': 'touch "$TEST_DIST/CodexUsageStatus-$VERSION-macos-$BUILD_ARCH.dmg"',
      'bin/ditto': 'touch "$6"',
      'bin/openssl': 'echo fixture-checksum'
    })) {
      const path = join(root, name);
      await writeFile(path, `#!/bin/sh\n${body}\n`);
      await chmod(path, 0o755);
    }
    const result = spawnSync('/bin/bash', [join(root, 'scripts/package-all-macos.sh')], {
      encoding: 'utf8',
      env: {
        ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`,
        BUILD_ARCH: 'x86_64', VERSION: '0.1.3', TEST_LOG: log, TEST_DIST: join(root, 'dist')
      }
    });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual((await readFile(log, 'utf8')).trim().split('\n'), ['arm64', 'x86_64', 'native']);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
