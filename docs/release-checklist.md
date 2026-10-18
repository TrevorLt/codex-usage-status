# Release Checklist

Use this checklist before publishing a GitHub release.

## Required checks

```sh
npm test
npm run test:native
BUILD_ARCH=arm64 npm run build:macos
BUILD_ARCH=x86_64 npm run build:macos
npm run package:macos:all
```

The native suite must emit `NATIVE TEST SUITE PASS` after every required harness has emitted its own PASS marker, including the login-item profile harness. A GUI process exiting zero before its assertions execute is not a pass. Run from a logged-in macOS graphical session; missing WindowServer access is a failure requiring investigation. The optional `npm run test:swiftpm` also exercises XCTest when it is included in the selected toolchain. The logo geometry verifier currently requires a developer-local `sharp` path and is not a portable CI prerequisite.

Confirm the generated app architecture:

```sh
lipo -archs "dist/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus"
codesign --verify --deep --strict --verbose=2 "dist/Codex Usage Status.app"
plutil -extract CFBundleIconFile raw -o - "dist/Codex Usage Status.app/Contents/Info.plist"
test -f "dist/Codex Usage Status.app/Contents/Resources/CodexUsageStatus.icns"
test -f dist/CodexUsageStatus-0.1.3-macos-arm64.dmg
test -f dist/CodexUsageStatus-0.1.3-macos-x86_64.dmg
```

Run a live local data-source check on a signed-in Codex desktop installation:

```sh
"dist/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus" --once
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
- A SHA256 checksum file for every uploaded ZIP and DMG.
- A verified custom `.VolumeIcon.icns` and Retina-ready DMG background.

Unsigned or ad-hoc signed ZIPs may trigger Gatekeeper warnings when downloaded from GitHub.
