# Privacy

Codex Usage Status is intentionally narrow: it shows local Codex usage status in the macOS menu bar.

## What the app reads

The app reads only the structured usage response returned by the local Codex app-server method:

```json
{"method":"account/rateLimits/read","id":2}
```

Codex itself owns authentication. This companion app receives the usage percentages and reset times that Codex returns through that local interface.

## What the app does not read

- It does not read `~/.codex/auth.json`.
- It does not read browser cookies, browser storage, sessions, OAuth credentials, refresh tokens, API keys, or account passwords.
- It does not scrape Codex UI pages, browser pages, screenshots, or OCR output.
- It does not modify the official Codex app bundle.
- It does not bypass, increase, reset, purchase, or route around usage limits.

## What leaves your Mac

This app does not upload usage data to this project, to the author, or to any third-party service.

The only network activity involved is whatever the official Codex app-server performs as part of Codex's own signed-in account flow. This project does not handle those credentials or proxy that traffic.

## Refresh behavior

The normal adaptive cadence is 30 seconds during startup/activity, 60 seconds after 90 seconds without a change, and 120 seconds after 5 minutes without a change. Automatic queries never start more often than every 30 seconds. Failed refreshes retry after 300 seconds, and a manual refresh is always available.

The app keeps the last successful reading in memory while it revalidates. After wake or a failed request, the reading is marked stale; it is not uploaded or written to a disk usage cache. A local redraw hides a window after its known reset time without making another account request.
