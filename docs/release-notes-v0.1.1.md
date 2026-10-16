# CodexUsageStatus v0.1.1

CodexUsageStatus is a small, read-only macOS menu-bar app for showing Codex 5-hour and 7-day usage at a glance.

## Highlights

- Includes the 1B-M CodexUsageStatus app icon in the app bundle.
- Keeps both 5H and 7D values visible in the menu bar.
- Uses a neutral template-style menu-bar rendering that follows macOS menu-bar contrast automatically.
- Uses red only when a remaining percentage is below 20%.
- Adapts successful refreshes between 30, 60, and 120 seconds based on recent activity.
- Retries failed reads after 300 seconds and recovers after sleep, wake, or a temporary network/app-server interruption.
- Keeps the last known good value visible while a refresh is unavailable, rather than showing an empty indicator.
- Uses the official local Codex app-server and does not read or transmit authentication tokens, browser data, API keys, or `~/.codex/auth.json`.
- Ships separate Apple Silicon (`arm64`) and Intel (`x86_64`) downloads.

## Downloads

- `CodexUsageStatus-0.1.1-macos-arm64.zip` — Apple Silicon Macs (M1/M2/M3/M4 and newer)
- `CodexUsageStatus-0.1.1-macos-x86_64.zip` — Intel Macs
- `SHA256SUMS.txt` — SHA-256 checksums for both ZIPs

## Installation note

These public artifacts are ad-hoc signed and are not notarized with an Apple Developer ID certificate. macOS Gatekeeper may therefore require the user to approve the app once through the normal Open confirmation flow. No global Gatekeeper bypass is required or recommended.

After copying `CodexUsageStatus.app` to `/Applications`, open the app once and enable Launch at Login from its menu if desired.

## Credit

This is an independent continuation based on [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status), originally created by [@tollenceld](https://github.com/tollenceld). The original project and MIT license remain credited.
