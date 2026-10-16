# Failure diagnostics

The menu-bar `?` badge means the latest refresh did not produce a usable usage snapshot. It is intentionally a compact error indicator; the tooltip and Settings panel contain the actionable reason.

## Failure matrix

| Symptom or reason | Meaning | Current handling |
| --- | --- | --- |
| Codex executable not found | The installed desktop app is outside the known layouts, or an explicit `CODEX_BIN` is stale/empty | Automatically checks legacy Codex, current ChatGPT-bundled shim, nested `CodexCLI.app`, and `/Applications` plus `~/Applications`; reports every checked path |
| App-server could not be launched | The candidate exists but macOS could not start it | Reports a launch failure; check the Codex install and normal macOS security approval |
| App-server exits before a response | Codex CLI starts but terminates before returning the usage RPC result | Reports the exit status immediately instead of waiting for the full timeout |
| Not signed in / unauthorized | The local Codex app-server cannot authorize the account | Reports that Codex must be opened and signed in, without displaying raw server text |
| Usage API not found | The installed Codex version does not expose `account/rateLimits/read` | Reports that Codex should be updated |
| Unsupported or missing usage response | The protocol returned malformed data or no usable limit windows | Keeps the raw response out of the UI and asks for a Codex update/diagnostic check |
| App-server timeout | The local process or its upstream request did not answer within 20 seconds | Reports timeout; manual refresh and the existing retry/recovery policy remain available |
| Sleep/wake or transient network failure after a successful read | A previously valid snapshot could not be refreshed | Keeps the last good reading marked stale, coalesces wake/network recovery, and avoids concurrent requests |
| Fresh install with no successful read yet | There is no safe last-known value to display | Shows the error badge and reason rather than inventing 100% or persisting account-specific quota to disk |
| Wrong architecture ZIP | The app usually fails to launch before it can render a badge | Choose the `arm64` package for Apple Silicon or `x86_64` for Intel; this is distinct from a running red `?` badge |
| Gatekeeper or quarantine block | macOS stopped the app before its process started | Use the normal macOS Open/Privacy & Security approval flow; do not disable Gatekeeper or remove quarantine globally |
| Hidden by a menu-bar manager | The item is running but placed in Hidden Bar/Bartender overflow | Expand the manager and move CodexUsageStatus into its visible section; this does not produce a `?` badge |

## What the app does not do

- It does not read `~/.codex/auth.json`, browser cookies, API keys, OAuth tokens, prompts, or chat history.
- It does not copy or persist raw app-server responses.
- It does not silently fall back to a browser or a third-party network endpoint.
- It does not treat a failed first read as 100% remaining.

## Diagnostic information to report

When opening an issue, include only:

- CodexUsageStatus version and selected architecture.
- macOS version and whether Codex is installed as `Codex.app` or `ChatGPT.app`.
- The safe message shown in Settings.
- Whether the official Codex app is open and signed in.

Never include `~/.codex/auth.json`, cookies, access tokens, API keys, raw JSON-RPC output, or usage screenshots containing account information.
