# Codex Usage Status

An independent macOS menu-bar companion for showing Codex usage at a glance.

![Codex Usage Status current menu-bar badge](docs/assets/menu-bar-badge-current.png)

This repository is an independent continuation based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld). The original project and its MIT license remain credited; this repository is maintained independently.

## Current design

The menu-bar badge uses a compact side-labeled double-ring layout:

- left ring group: 5-hour remaining percentage (`5H`)
- right ring group: weekly / 7-day remaining percentage (`7D`)
- ring progress: remaining quota status
- ring center number: remaining percentage
- no capsule background, so it stays visually lightweight beside the other macOS status items

The normal badge uses macOS's native menu-bar template tinting. This lets the icon follow the surrounding status-bar contrast automatically instead of forcing a fixed light/dark color. When either remaining value falls below 20%, that window turns system red as an actionable warning; normal values remain neutral.

The menu-bar badge is the primary interface. Clicking it exposes only the necessary actions: Refresh, Display Style, Settings, and Quit.

Double Ring is the default display style. A larger accessibility-oriented style is available from Display Style > Large Readout. Large Readout keeps both values visible while prioritizing larger readable numbers with weak `5H` / `7D` labels and thin status lines.

## Adaptive refresh

The app uses a conservative adaptive schedule so active usage is detected quickly without polling continuously:

- normal baseline: refresh every 120 seconds
- significant change: when either window drops by at least 5 percentage points, refresh again after 30 seconds
- active-change window: stay at the 30-second cadence while the significant drop is within the last 60 seconds
- stable backoff: after stability returns, back off to 120 seconds, then 240 seconds, and finally 300 seconds
- failed request: retry after 300 seconds
- manual refresh: always available from the menu

The current build never schedules automatic refreshes more frequently than every 30 seconds. `CODEX_USAGE_REFRESH_SECONDS` can change the normal baseline, but cannot lower that 30-second floor.

## Safety model

This app only calls the official local Codex app-server method `account/rateLimits/read`. It does not modify Codex, does not read `~/.codex/auth.json`, and does not handle tokens, cookies, sessions, OAuth credentials, API keys, or browser data.

See [PRIVACY.md](PRIVACY.md) for the user-facing privacy summary and [SECURITY.md](SECURITY.md) for the hard engineering boundaries.

## Requirements

- macOS 13 or later
- Codex desktop installed and already signed in
- The local Codex app-server executable must be available at `/Applications/Codex.app/Contents/Resources/codex` or supplied through `CODEX_BIN`

## Install from release

1. Download the latest release ZIP for your Mac from [GitHub Releases](https://github.com/TrevorLt/codex-usage-status/releases):
   - Apple Silicon: `CodexUsageStatus-<version>-macos-arm64.zip`
   - Intel: `CodexUsageStatus-<version>-macos-x86_64.zip`
2. Unzip it.
3. Move `CodexUsageStatus.app` to `/Applications`.
4. Open `CodexUsageStatus.app`.

The app is menu-bar-only, so it does not appear in the Dock. To launch it automatically after login, add `CodexUsageStatus.app` in macOS System Settings > General > Login Items.

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

To override the normal baseline interval while keeping the 30-second minimum:

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
