# Codex Usage Status v0.1.4

This release adds earned-reset reminders and smoother feedback for usage refreshes and reset recovery.

## Added

- Show a compact amber badge dot when an available Codex reset credit expires within 72 hours.
- Add a stable menu reminder with an action to use the earliest known-expiring credit and an option to dismiss the current reminder batch.
- Show every available reset credit's known expiration in About, alongside the live next-refresh countdown.
- Animate normal quota changes smoothly and show a brief system-green recovery animation only after a reset is confirmed by a fresh usage read.
- Add a deterministic animation previewer, pure animation-frame tests, mock reset-flow coverage, reset-expiry edge cases, and expanded AppKit badge-rendering checks.
- Bind uncertain reset retries to a one-way account fingerprint and recheck the active account immediately before sending the consume request.

## Changed

- Format every timestamp in About with the same formatter and the current local time zone.
- Remove the separator dot between the 5-hour and 7-day readings in both display modes.
- Add reset, animation, and test guidance to the README, with recorded previews for both badge styles.
- Export README animation GIFs from the production AppKit renderer using synthetic local readings; add a reminder illustration for both badge styles.

## Safety and verification

- Reset use still requires explicit confirmation. Mock flow tests use a fake client and never contact the account reset endpoint.
- Local test results and their graphical-session/XCTest limits are documented in the release checklist. No physical sleep/wake behavior or Intel hardware test is claimed by synthetic harnesses.
- Local builds are ad-hoc signed unless a Developer ID identity is provided. This release does not claim notarization.

## Downloads

- Apple Silicon: `CodexUsageStatus-0.1.4-macos-arm64.dmg` or `.zip`
- Intel: `CodexUsageStatus-0.1.4-macos-x86_64.dmg` or `.zip`
- Verify downloaded artifacts with `SHA256SUMS.txt`.

## Credit

Based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld), under the preserved MIT license. Independent maintenance does not imply affiliation with OpenAI.
