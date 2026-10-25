# Contributing

Keep the project boring, narrow, and safe.

## Rules for changes

- Do not read or parse credential files.
- Do not add browser scraping, cookie access, OCR, login automation, account switching, or quota-bypass behavior.
- Keep refreshes conservative.
- Do not lower the automatic refresh floor below 30 seconds without a measured, documented reason.
- Keep the normal adaptive cadence at 30/60/120 seconds unless a change includes updated resource and freshness evidence.
- Prefer the official local Codex app-server protocol.
- Keep the menu-bar title compact enough for crowded macOS menu bars.

## Local checks

```sh
npm test
bash scripts/test-wake-recovery.sh
BUILD_ARCH=arm64 npm run build:macos
BUILD_ARCH=x86_64 npm run build:macos
dist/'Codex Usage Status.app'/Contents/MacOS/CodexUsageStatus --once
```
