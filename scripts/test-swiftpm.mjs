// Isolate test outputs and compensate for mismatched public/private manifest
// interfaces in some CLT upgrades. The compiler's VFS overlay is read-only:
// this never edits or removes files from the developer toolchain.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const xctest = spawnSync('xcrun', ['--find', 'xctest'], { encoding: 'utf8' });
if (xctest.status !== 0) {
  console.error('The selected developer toolchain does not include XCTest. Use npm run test:native with Command Line Tools, or select a full Xcode installation to run this additional suite.');
  process.exit(2);
}
const lookup = spawnSync('xcrun', ['--find', 'swiftc'], { encoding: 'utf8' });
if (lookup.status !== 0) { console.error('A Swift developer toolchain is required.'); process.exit(1); }
const manifestDirectory = resolve(dirname(lookup.stdout.trim()), '../lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule');
const temporary = mkdtempSync(join(tmpdir(), 'codex-swiftpm-tests-'));
const roots = [];
const compilerHeader = text => text.split('\n').find(line => line.startsWith('// swift-compiler-version:'));
if (existsSync(manifestDirectory)) {
  for (const name of readdirSync(manifestDirectory).filter(name => name.endsWith('.private.swiftinterface'))) {
    const privatePath = join(manifestDirectory, name);
    const publicPath = join(manifestDirectory, name.replace('.private.swiftinterface', '.swiftinterface'));
    if (existsSync(publicPath) && compilerHeader(readFileSync(privatePath, 'utf8')) !== compilerHeader(readFileSync(publicPath, 'utf8'))) {
      roots.push({ type: 'file', name: privatePath, 'external-contents': publicPath });
    }
  }
}
const args = ['test', '--package-path', join(root, 'macos/CodexUsageStatus'), '--scratch-path', join(temporary, 'build'),
  '-Xswiftc', '-module-cache-path', '-Xswiftc', join(temporary, 'module-cache')];
if (roots.length) {
  const overlay = join(temporary, 'manifest-interfaces.json');
  writeFileSync(overlay, JSON.stringify({ version: 0, roots }));
  args.push('-Xmanifest', '-vfsoverlay', '-Xmanifest', overlay,
    '-Xmanifest', '-module-cache-path', '-Xmanifest', join(temporary, 'manifest-cache'));
  console.log('Using a temporary VFS overlay for mismatched manifest interfaces; system files are unchanged.');
}
args.push(...process.argv.slice(2));
const result = spawnSync('swift', args, { stdio: 'inherit' });
if (result.error) { console.error(result.error.message); process.exit(1); }
process.exit(result.status ?? 1);
