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

## Compatibility note

The v0.1.1 release only checked `/Applications/Codex.app/Contents/Resources/codex`. Current ChatGPT desktop installations may place Codex under `ChatGPT.app/Contents/Resources/codex-cli/`. v0.1.2 checks both known families of layouts.

## Verification

- Node tests pass.
- Path-resolution harness passes.
- Fetcher lifecycle/error-redaction harness passes.
- Sleep/wake recovery harness passes.
- 1B-M icon geometry and packaging checks pass.
- arm64 and x86_64 app bundles build and strict ad-hoc signature verification passes.

## Credit

This is an independent continuation based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld). The original project and MIT license remain credited.
