# CodexUsageStatus v0.1.2

This release improves first-run compatibility and makes failed refreshes diagnosable instead of showing only an undifferentiated question mark.

## Highlights

- Automatically discovers common `Codex.app` and `ChatGPT.app` layouts in `/Applications` and `~/Applications`.
- Supports the legacy Codex executable, the current `codex-cli/bin/codex` shim, and the nested `CodexCLI.app` app-server executable.
- Treats empty `CODEX_BIN` values as unset while still honoring a valid explicit override.
- Detects app-server early exits immediately instead of misreporting them as a full timeout.
- Distinguishes missing executable, launch failure, early exit, timeout, authentication, unsupported API, and malformed response cases with safe actionable text.
- Does not display raw app-server stderr or server error text that could contain sensitive material.
- Keeps the existing local-only, read-only app-server safety boundary and neutral template menu-bar display.
- Keeps the existing adaptive refresh, sleep/wake recovery, last-good stale display, and below-20% red warning behavior.
- Adds architecture-specific DMG installers with a Finder drag-to-Applications layout using the 1B-M app icon and the project's charcoal/lavender visual language.
- Gives the mounted installer disk the 1B-M volume icon, uses a Retina-ready background, and presents the app as `Codex Usage Status` while retaining the internal executable name for compatibility.

## Compatibility note

The v0.1.1 release only checked `/Applications/Codex.app/Contents/Resources/codex`. Current ChatGPT desktop installations may place Codex under `ChatGPT.app/Contents/Resources/codex-cli/`. v0.1.2 checks both known families of layouts.

## Verification

- Node tests pass.
- Path-resolution harness passes.
- Fetcher lifecycle/error-redaction harness passes.
- Sleep/wake recovery harness passes.
- 1B-M icon geometry and packaging checks pass.
- arm64 and x86_64 app bundles build and strict ad-hoc signature verification passes.
- arm64 and x86_64 ZIP and DMG checksums, disk-image verification, and installer payload checks pass.

## Download guide

1. Choose `arm64` for Apple Silicon Macs (M1/M2/M3/M4 and newer), or `x86_64` for Intel Macs.
2. Recommended: download the matching DMG, open it, and drag `Codex Usage Status.app` to the `Applications` shortcut.
3. Alternative: download the matching ZIP, unzip it, and move `Codex Usage Status.app` to `/Applications`.
4. Open the app. If macOS shows its normal Gatekeeper confirmation, choose Open after checking that the app came from this repository.
5. Open the menu-bar badge and enable Launch at Login if desired. Verify the matching ZIP/DMG with `SHA256SUMS.txt`.

## Credit

This is an independent continuation based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld). The original project and MIT license remain credited.
