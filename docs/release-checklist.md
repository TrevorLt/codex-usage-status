# Release Checklist

Use this checklist before publishing a GitHub release.

## Required checks

```sh
npm test
bash scripts/test-wake-recovery.sh
node branding/verify-logo.mjs
BUILD_ARCH=arm64 npm run build:macos
BUILD_ARCH=x86_64 npm run build:macos
npm run package:macos:all
```

Confirm the generated app architecture:

```sh
lipo -archs dist/CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus
codesign --verify --deep --strict --verbose=2 dist/CodexUsageStatus.app
plutil -extract CFBundleIconFile raw -o - dist/CodexUsageStatus.app/Contents/Info.plist
test -f dist/CodexUsageStatus.app/Contents/Resources/CodexUsageStatus.icns
```

Run a live local data-source check on a signed-in Codex desktop installation:

```sh
dist/CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus --once
```

## Safety checks

- Confirm `SECURITY.md` still matches the implementation.
- Confirm no code reads `~/.codex/auth.json`.
- Confirm no code reads browser cookies, browser storage, screenshots, OCR output, or account tokens.
- Confirm refresh intervals remain conservative.
- Confirm the 1B-M app icon is present in `Contents/Resources` and declared in `Info.plist`.
- Confirm the app only calls `account/rateLimits/read` through the local Codex app-server.

## Public release quality

Local builds are ad-hoc signed by default. That is fine for personal use and source builds, but a polished public release should use:

- Apple Developer ID signing.
- Apple notarization.
- Separate `arm64` and `x86_64` artifacts, or a tested universal app.
- A SHA256 checksum file for every uploaded ZIP.

Unsigned or ad-hoc signed ZIPs may trigger Gatekeeper warnings when downloaded from GitHub.
