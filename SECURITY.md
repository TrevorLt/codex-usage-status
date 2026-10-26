# Security policy

This project is intentionally narrow: it displays Codex usage status and nothing else.

## Hard boundaries

- It does not read, print, store, upload, transform, or proxy tokens, cookies, sessions, OAuth credentials, refresh tokens, or API keys.
- It does not read `~/.codex/auth.json`.
- It does not scrape browser state, browser cookies, web pages, screenshots, or OCR output.
- It does not simulate login or retry login flows.
- It does not modify the official Codex app bundle.
- It does not bypass, increase, or purchase usage limits. It consumes an earned reset only after the user explicitly confirms that action.

## Data source

Usage is read through the official local Codex app-server method:

```json
{"method":"account/rateLimits/read","id":2}
```

After explicit confirmation, the app can also send `account/rateLimitResetCredit/consume`. Every consume request requires a specific credit ID observed on the verified account and a persisted idempotency key for safe retries. The app never asks the server to pick a credit, including after an account switch. A follow-up read from a different account is not displayed as a confirmed reset.

Pending requests are bound to a hashed account identifier. Unbound legacy requests and requests belonging to a different account cannot be sent; clearing one requires a separate explicit choice. Polling is suspended during redemption so older reads cannot replace its result.

Codex itself owns authentication and calls its own backend. This project receives only the structured rate-limit response returned by app-server.

## Refresh policy

The normal adaptive menu-bar cadence is 30 seconds during startup/activity, 60 seconds after 90 seconds without a valid usage change, and 120 seconds after 5 minutes without a change. Automatic queries have a hard 30-second floor. Failed refreshes back off to 300 seconds. Keep refreshes conservative; usage status does not need sub-second polling.

The last successful snapshot is retained only in process memory. It is marked stale after wake or errors, expires after 24 hours, and is not persisted to disk because the local response does not provide a safe account binding for a saved snapshot.

## If this stops working

Stop at the official boundary. Do not add cookie scraping, token extraction, browser automation, OCR, or patched-app workarounds as fallbacks.
