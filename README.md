# Codex Usage Status

Small macOS menu-bar app for showing Codex usage at a glance.

![Codex Usage Status menu-bar badge](docs/assets/menu-bar-badge.png)

It displays usage as a compact side-labeled double-ring badge:

- left ring group: 5-hour remaining percentage
- right ring group: weekly remaining percentage
- ring progress: remaining quota status
- ring center number: remaining percentage
- side labels: `5H` and `7D`

The menu-bar badge is the primary interface. Clicking it only exposes the necessary actions: Refresh, Settings, and Quit.

Double Ring is the default display style. It uses no capsule background, and each label sits beside its own ring instead of inside the ring. A larger accessibility-oriented style is available from Display Style > Large Readout. Large Readout keeps the same two values visible in the menu bar, but prioritizes even larger readable numbers with weak `5H` / `7D` labels and thin status lines.

## Safety model

This app only calls the official local Codex app-server method `account/rateLimits/read`. It does not modify Codex, does not read `~/.codex/auth.json`, and does not handle tokens, cookies, sessions, OAuth credentials, API keys, or browser data.

See [PRIVACY.md](PRIVACY.md) for the user-facing privacy summary and [SECURITY.md](SECURITY.md) for the hard engineering boundaries.

## Requirements

- macOS 13 or later
- Codex desktop installed at `/Applications/Codex.app`
- You are already signed in to Codex

## Install from release

1. Download the latest release ZIP for your Mac from [GitHub Releases](https://github.com/tollenceld/codex-usage-status/releases/latest):
   - Apple Silicon: `CodexUsageStatus-<version>-macos-arm64.zip`
   - Intel: `CodexUsageStatus-<version>-macos-x86_64.zip`
2. Unzip it.
3. Move `CodexUsageStatus.app` to `/Applications`.
4. Open `CodexUsageStatus.app`.

The app is a menu-bar-only app, so it does not appear in the Dock. Optional: add it to macOS System Settings > General > Login Items.

Unsigned GitHub builds may trigger macOS Gatekeeper warnings. For a public polished release, sign with an Apple Developer ID and notarize the app.

## Known limitations

- Codex desktop must be installed at `/Applications/Codex.app`, unless `CODEX_BIN` is set for development.
- You must already be signed in to Codex.
- Live usage depends on Codex's local app-server method `account/rateLimits/read`; if that local interface changes, this app may need an update.
- The app shows usage only. It cannot buy credits, switch accounts, retry login, or change limits.
- Local builds are ad-hoc signed by default. Downloaded release ZIPs may show Gatekeeper warnings until a notarized build is available.

## Build from source

For source builds:

- Swift toolchain / Xcode Command Line Tools
- Node.js 20 or later for tests and the optional CLI probe

```sh
npm test
npm run build:macos
npm run start:macos
```

The build script defaults to the Mac's hardware architecture. On Apple Silicon this creates an `arm64` app, even if Node.js is running under Rosetta. To build a specific architecture:

```sh
BUILD_ARCH=arm64 npm run build:macos
BUILD_ARCH=x86_64 npm run build:macos
```

To install into `/Applications`:

```sh
npm run install:macos
```

The app is a menu-bar-only app, so it does not appear in the Dock.

To change the menu-bar display, click the badge and choose Display Style:

- Double Ring: compact default with side labels and circular quota indicators.
- Large Readout: larger numbers with subtle status lines for easier reading.

Refresh scheduling is adaptive to reduce stale readings without polling aggressively:

- Normal operation refreshes every 120 seconds.
- A drop of at least 5 percentage points in either usage window schedules the next refresh after 60 seconds.
- If usage remains stable, the interval backs off to 120, then 240, and finally 300 seconds.
- Failed requests retry after 300 seconds.

The app never refreshes more often than once per 60 seconds. To override the normal interval:

```sh
CODEX_USAGE_REFRESH_SECONDS=180 npm run start:macos
```

## CLI probe

The CLI uses the same safe app-server source and is useful for debugging:

```sh
npm run usage
npm run usage:json
```

The CLI output remains text-based for logs and tests even though the macOS menu-bar UI is a graphic badge.

If your Codex binary lives somewhere else:

```sh
CODEX_BIN=/path/to/codex npm run usage
```

## Release package

```sh
npm run package:macos
npm run package:macos:all
```

`package:macos` creates a zipped `.app` for the current Mac architecture. `package:macos:all` creates both `arm64` and `x86_64` ZIPs plus `SHA256SUMS.txt` in `dist/`.

Release ZIPs are architecture-specific:

- `CodexUsageStatus-<version>-macos-arm64.zip` for Apple Silicon Macs.
- `CodexUsageStatus-<version>-macos-x86_64.zip` for Intel Macs.

For another MacBook, the most reliable source-build path is to clone the repository on that Mac and run `npm run install:macos`; it will build the correct native architecture there.

## Repository layout

- `macos/CodexUsageStatus/`: native AppKit menu-bar app.
  - `App/`: status item lifecycle, menu actions, refresh scheduling, and configuration.
  - `Codex/`: local Codex app-server JSON-RPC client.
  - `Domain/`: rate-limit response models and usage normalization.
  - `UI/`: badge styles and AppKit drawing code.
- `src/`: Node CLI probe for diagnostics and tests.
- `test/`: Node tests for response normalization and sensitive-output redaction.
- `scripts/`: build, run, install, and release packaging scripts.
- `.github/workflows/`: CI and release artifact workflows.
- `docs/`: architecture, structure, release, and upstream integration notes.

See [docs/project-structure.md](docs/project-structure.md) for the source layout and dependency boundaries.
