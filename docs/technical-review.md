# Technical review

## Current architecture

The app is intentionally split into two pieces:

- Native macOS UI: AppKit status item in `macos/CodexUsageStatus`.
- Probe/test layer: Node client and formatter tests in `src/` and `test/`.

The production app does not need Node at runtime. It directly spawns:

```sh
<resolved Codex executable> app-server --listen stdio://
```

The resolver checks an explicit non-empty `CODEX_BIN` first, then common `Codex.app` and `ChatGPT.app` layouts in `/Applications` and `~/Applications`, including the current embedded `codex-cli` shim and nested `CodexCLI.app` executable.

Then it sends the official JSON-RPC method:

```json
{"method":"account/rateLimits/read","id":2}
```

## Why this is safer than patching Codex.app

Patching the packaged Codex desktop bundle breaks signing and ASAR integrity assumptions. A companion app keeps Codex untouched and relies on the same official local app-server boundary used by supported integrations.

## Menu-bar display

The default menu-bar display is a side-labeled double-ring badge.

The left ring group represents the 5-hour window and the right ring group represents the 7-day weekly window. Each label sits beside its own ring rather than inside the ring, so the ring center only has to carry the remaining percentage number. The `5H` and `7D` labels are stacked into matching two-character micro-labels for visual balance. The badge intentionally avoids a capsule background so it feels like a native lightweight menu-bar status item instead of a separate floating control.

This keeps the menu-bar footprint narrow while making the two quota windows visually distinct. The click menu is intentionally minimal: Refresh, Display Style, Launch at Login, About, and Quit.

The optional Large Readout style is designed for readability. It uses larger monospaced numbers as the primary visual layer, keeps `5H` / `7D` as weak labels, and moves status expression into subtle bottom lines. It also avoids the capsule background.

## Refresh behavior

Refresh is intentionally conservative:

- automatic refresh every 30 seconds during startup/activity, then 60 seconds after 90 seconds of stability and 120 seconds after 5 minutes of stability
- 30-second minimum between automatic queries
- a finite `CODEX_USAGE_REFRESH_SECONDS` value opts into a fixed success cadence, with the same 30-second floor
- failed refreshes back off to 300 seconds
- no overlapping refreshes
- wake and network recovery coalesce into one recovery refresh
- last-known values remain visible as stale in memory while a new read is attempted; no disk usage cache is used
- manual refresh from the menu
- 20-second timeout per app-server request

## Known limitations

- Custom installations outside the known application layouts require `CODEX_BIN` in a developer/source launch.
- Public release builds should be Developer ID signed and notarized.
- The menu-bar companion cannot draw inside the official Codex desktop window. That requires an upstream Codex desktop change.
- The repository's app bundle includes the 1B-M `CodexUsageStatus.icns` icon; the menu-bar badge itself remains a separate native template image.

## Good next issues

- User preference for badge color thresholds or icon-only fallback.
- Keep the documented per-user LaunchAgent/Login Items setup aligned with the installed app.
- Notarized release pipeline.
- Better error menu with a copyable diagnostic summary that still redacts secrets.
