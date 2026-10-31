# Codex Usage Status v0.1.4

This release adds earned-reset reminders, safer reset recovery, reliable native app startup, and purchased-credit visibility when the 5-hour quota is fully used.

## Added

- Show a compact amber badge dot when an available Codex reset credit expires within 72 hours.
- Add a stable menu reminder with an action to use the earliest known-expiring credit and an option to dismiss the current reminder batch.
- Show every available reset credit's known expiration in About, alongside the live next-refresh countdown.
- Show purchased credit balance in the badge and hover details only after the raw 5-hour usage reaches 100%; keep earned reset credits distinct.
- Animate normal quota changes smoothly and show a brief system-green recovery animation only after a reset is confirmed by a fresh usage read.
- Add deterministic animation previews, reset-flow and expiry boundary coverage, purchased-credit formatting and cadence coverage, and expanded AppKit badge-rendering checks.

## Changed

- Bind uncertain reset retries to the verified account and a specific credit ID; reuse the saved idempotency key and never let a newly selected credit replace a pending request.
- Serialize polling with reset redemption, retain pending retries when no credits remain, and clear confirmed redemptions even when the follow-up usage read fails.
- Use the native hardware architecture during local startup, wait for old app copies to stop, verify the launched executable path, and restore the login task after a failed launch.
- Validate the app architecture and version before DMG packaging and restore the native build after producing both architectures.
- Format About timestamps in the current local time zone, remove the separator between quota readings, and export README previews from the production AppKit renderer.

## Safety and verification

- Reset use requires explicit confirmation, a verified account, and a specific credit ID. Reset-flow tests use a fake client and do not consume a real reset.
- The app reads usage through the official local Codex app-server. It does not read `~/.codex/auth.json`, browser data, or account tokens.
- Local builds are ad-hoc signed unless a Developer ID identity is provided. This release does not claim notarization; downloaded copies may require the normal Gatekeeper approval flow.
- No physical sleep/wake behavior or Intel hardware test is claimed by synthetic harnesses.

## Downloads

- Apple Silicon: `CodexUsageStatus-0.1.4-macos-arm64.dmg` or `.zip`
- Intel: `CodexUsageStatus-0.1.4-macos-x86_64.dmg` or `.zip`
- Verify downloaded artifacts with `SHA256SUMS.txt`.

## Credit

Based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld), under the preserved MIT license. Independent maintenance does not imply affiliation with OpenAI.
