# Codex Usage Status v0.1.3

This release combines the reliability work from the previous development builds with the menu-bar usability and warning-color fixes.

## Reliability and data handling

- Treat malformed JSON-RPC results as controlled errors instead of allowing a Foundation exception to terminate the menu-bar app.
- Buffer stdout by complete byte lines so split UTF-8 characters survive, while bounding line memory.
- Consume app-server stderr continuously, retain only bounded diagnostic classification state, and bound process/pipe cleanup.
- Keep the neutral menu-bar mark as a native template layer while using a separate red overlay for depleted windows, including 0% remaining.
- Make CLI missing and partial quota data explicit, select windows by duration, and round remaining quota from the raw used percentage.
- Improve CLI executable discovery, process errors, request timer cleanup, safe diagnostics, and long-input redaction behavior.
- Keep warning percentages in the native menu-bar contrast color; only the low-usage ring or readout bar turns red. At 0%, the ring becomes a complete red warning ring.

## Installation and recovery

- Migrate the legacy app name and existing login LaunchAgent through staged replacement with recoverable backups.
- Give installed app copies a per-user instance lock so accidental duplicate launches do not create multiple monitors.
- Preserve an existing disabled login state during migration instead of silently enabling a new login item.
- Keep the wake/recovery path able to retain the last known display while a fresh local query is unavailable.
- Add a checkable Launch at Login menu item backed by the per-user LaunchAgent, preserving an existing custom `CODEX_BIN` configuration.
- Rename the diagnostics summary action from Settings... to About.

## Verification and release packaging

- Require native behavior tests, explicit success markers, and installer regressions before CI builds or release packaging.
- Add an isolated SwiftPM test wrapper for mismatched manifest interfaces left by some Command Line Tools installations; it does not modify the system toolchain.
- Publish separate Apple Silicon and Intel ZIP/DMG artifacts with SHA-256 checksums and the branded Retina-ready installer layout.

## Download guide

1. Choose `arm64` for Apple Silicon Macs (M1/M2/M3/M4 and newer), or `x86_64` for Intel Macs.
2. Recommended: download the matching DMG, open it, and drag `Codex Usage Status.app` to the `Applications` shortcut.
3. Alternative: download the matching ZIP, unzip it, and move `Codex Usage Status.app` to `/Applications`.
4. Open the app. If macOS shows its normal Gatekeeper confirmation, choose Open after checking that the app came from this repository.
5. Open the menu-bar badge and check Launch at Login if desired. Use `SHA256SUMS.txt` to verify the ZIP/DMG before opening it.

The local verification suite uses fake app-server responses and simulated workspace events; it does not claim a physical lid/sleep test, Intel hardware validation, or notarization. Local builds are ad-hoc signed by default, so downloaded copies may require the normal macOS Gatekeeper approval flow.

## Credit

Based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld), under the preserved MIT license. Independent maintenance and these reliability changes do not imply affiliation with OpenAI.
