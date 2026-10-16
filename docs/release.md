# Release guide

For a full pre-release pass, also use [release-checklist.md](release-checklist.md).

## Local release artifact

```sh
npm test
npm run package:macos:all
```

Output:

- `dist/CodexUsageStatus.app`
- `dist/CodexUsageStatus-<version>-macos-arm64.zip`
- `dist/CodexUsageStatus-<version>-macos-x86_64.zip`
- `dist/SHA256SUMS.txt`

The single-architecture package script builds the app for the Mac's hardware architecture by default. On Apple Silicon, this avoids accidentally creating an Intel-only app from a Rosetta Node.js shell. To package a specific architecture:

```sh
BUILD_ARCH=arm64 npm run package:macos
BUILD_ARCH=x86_64 npm run package:macos
```

## Signing

By default, the local build is ad-hoc signed:

```sh
CODESIGN_IDENTITY=- npm run build:macos
```

For a public release, use a Developer ID certificate and notarization:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" npm run package:macos
```

Notarization is intentionally not automated in this repository because it requires Apple developer credentials.

## Architecture

The local package builds for the detected hardware architecture unless `BUILD_ARCH` is set. GitHub Actions can produce a macOS artifact on the runner architecture. If universal releases are needed, build separate `arm64` and `x86_64` artifacts or add a universal build step after confirming both targets compile in CI.

## User install flow

For a release ZIP:

1. Download and unzip the release artifact.
2. Move `CodexUsageStatus.app` to `/Applications`.
3. Open the app.
4. Optional: add it to macOS System Settings > General > Login Items.

The package contains the `CodexUsageStatus.icns` app icon. The menu-bar badge is still rendered separately as a native template image so it can follow macOS status-bar contrast and show the 5H/7D readings.

For source:

```sh
npm run install:macos
```
