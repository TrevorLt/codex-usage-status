import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, copyFile, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

test('DMG packaging rejects mismatched architecture or version before creating an image', async () => {
  const root = await mkdtemp(join(tmpdir(), 'codex-package-test-'));
  try {
    await mkdir(join(root, 'scripts'));
    await mkdir(join(root, 'bin'));
    await mkdir(join(root, 'dist', 'Codex Usage Status.app'), { recursive: true });
    await copyFile(new URL('../scripts/package-dmg.sh', import.meta.url), join(root, 'scripts/package-dmg.sh'));
    for (const [name, body] of Object.entries({
      lipo: 'echo arm64',
      plutil: 'echo 0.1.3',
      xcrun: 'echo "packaging prerequisites reached" >&2; exit 80'
    })) {
      const path = join(root, 'bin', name);
      await writeFile(path, `#!/bin/sh\n${body}\n`);
      await chmod(path, 0o755);
    }
    for (const [arch, version, mismatched] of [
      ['x86_64', '0.1.3', true], ['arm64', '9.9.9', true], ['arm64', '0.1.3', false]
    ]) {
      const result = spawnSync('/bin/bash', [join(root, 'scripts/package-dmg.sh')], {
        encoding: 'utf8',
        env: { ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`, BUILD_ARCH: arch, VERSION: version }
      });
      assert.equal(result.error, undefined);
      assert.equal(result.status, mismatched ? 1 : 80);
      assert.match(result.stderr, mismatched ? /Rebuild before packaging/ : /packaging prerequisites reached/);
      if (mismatched) assert.doesNotMatch(result.stderr, /packaging prerequisites reached/);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
