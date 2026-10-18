# Reliability fixes (unreleased)

This development work follows v0.1.2. Published v0.1.2 assets remain unchanged; a local verification build can use `VERSION=0.1.3-dev`.

## Changes

- Treat malformed JSON-RPC results as controlled errors rather than allowing a Foundation exception to terminate the menu-bar app.
- Buffer stdout by complete byte lines so split UTF-8 characters survive; bound line memory.
- Consume stderr while app-server runs, retain bounded diagnostic classification state, and bound process/pipe cleanup.
- Keep neutral menu-bar marks as a native template layer while separate red overlays identify depleted windows, including 0% remaining.
- Make CLI missing/partial quota data explicit, select windows by duration, and round remaining quota from the raw used percentage.
- Improve CLI executable discovery, process errors, request timer cleanup, safe diagnostics, and long-input redaction behavior.
- Migrate the legacy app name and existing login LaunchAgent using staged replacement and recoverable backups. Updated app copies share a per-user instance lock.
- Require native behavior tests, explicit success markers and installer regressions before CI builds or release packaging.
- Provide an isolated SwiftPM test wrapper for mismatched manifest interfaces left by some Command Line Tools installations; it does not modify the toolchain.

## Verification

The repair plan and final local validation record are tracked separately. Fake app-server responses test failures without accessing account data. Simulated workspace events are not a physical lid/sleep test; cross-compilation and signature verification are not Intel/macOS 13 hardware validation.

## Credit

Based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld), under the preserved MIT license. Independent maintenance and these reliability changes do not imply affiliation with OpenAI.
