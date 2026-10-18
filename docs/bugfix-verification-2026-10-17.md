# Reliability repair verification — 2026-10-17

Baseline: `v0.1.2` (`b4ad618`). Work was implemented by five scoped 6-luna xhigh workers and integrated/tested by the main agent. See [the complete plan](bugfix-plan-2026-10-17.md).

## Resolution matrix

| Finding | Resolution | Verification |
|---|---|---|
| N1: null/scalar result crashes | Validate the RPC result type before serialization; report a controlled protocol error | Original null and numeric reproducers now exit normally; real child-process fixtures reject both without a signal |
| N2: stderr backpressure | Drain diagnostics while the child runs; retain bounded category state | Original 2 MiB stderr reproducer succeeds in about 0.334 s instead of timing out after 20 s |
| N3: UTF-8 chunks lost | Accumulate bounded byte lines before decoding | Original fragmented-Unicode reproducer and real child-process fragmentation pass |
| N4: no red at 0% | Independent red warning layer includes the number at 0% | Actual composed-button pixel tests pass at 0/19/20% for both styles and appearances |
| Warning-state contrast | Neutral image remains a native template while the warning layer stays colored | Mixed low/normal composition and template ownership assertions pass |
| C1/C2/C6: missing quota, mislabeled windows, rounding | Explicit unknown/absent data; duration-based selection; raw-first remaining calculation | Original independent CLI audit passes; text output uses `--` rather than `null%`; unrelated provider buckets are rejected |
| C3: unsafe RPC diagnostics | Allow only safe error categories; omit raw stdout/stderr fields | Synthetic secret sentinel does not reach CLI error output |
| C4/C5: path discovery, spawn errors, lingering timers | Discover common app layouts, handle process/stream errors and clear pending timers; bound shutdown | Missing executable, early exit, timeout and TERM/KILL fixtures pass |
| Long diagnostic regex input | Linear segment scanning and bounded diagnostic handling | Repository long-input regression passes |
| Legacy app and login migration | Staged, validated replacement with recoverable backups; preserve existing LaunchAgent state | Mocked failure/rollback cases and this Mac's actual upgrade succeed |
| Multiple monitor instances | Per-user lock shared by updated copies; `--once` bypasses it | Cross-process contention test and actual installed second-launch test pass |
| CI coverage | Node + marker-checked native tests + XCTest before build/package jobs | Workflow syntax/structure checked locally; remote execution not triggered |
| SwiftPM/toolchain mismatch | Explicit Swift 6 manifest and isolated read-only VFS overlay for mismatched interfaces; clear missing-XCTest diagnosis | Manifest compilation advances using the overlay; system toolchain is unchanged. Full XCTest was not run on this CLT-only Mac |

The CLI treats a nonempty `CODEX_BIN` as authoritative and reports a controlled error if it is stale. Native discovery preserves the existing behavior of trying the override first and then known installations. This difference is intentional and does not permit credential or browser fallbacks.

## Executed checks

- `npm test`: **24/24 passed**.
- Independent CLI audit from the earlier review: **8/8 passed**, unchanged expected behavior.
- `npm run test:native`: **all seven harnesses passed**, each with exactly one recognized PASS marker: policy/domain, path resolution, fetcher lifecycle, real native process faults, installer migration, wake recovery, badge rendering.
- Native process faults: **12 scenarios passed**, including 2 MiB stderr, malformed result types, early-exit output races, UTF-8, line overflow, inherited descriptors, ignored TERM and the 20-second timeout.
- Independent original native audit: **12/12 passed**, including **30,081 deterministic domain/policy/ASCII assertions**.
- Composed-button render checks: **57 assertions passed**; wake/recovery: **17 assertions passed**.
- Updated fetcher stress check: **100 queries, 100 fixture processes, zero survivors**, about **6.004 seconds**.
- Full application built as **arm64 and x86_64**, strict ad-hoc signature verification passed. The local CLT emitted a warning that its compatibility-pack archive lacks an x86_64 slice; the executable linked and passed signature checks, but Intel runtime compatibility still needs real hardware verification.
- Shell syntax, Node syntax, YAML/JSON and `git diff --check` passed.
- `npm run test:swiftpm`: **exit 2, not counted as a pass**. The selected Command Line Tools installation lacks XCTest. The workflow retains the XCTest gate on full-Xcode hosted runners; its actual execution remains pending a push.

The 30/60/120-second policy and 300-second failure retry implementation are unchanged. Tests use fake account responses except for the final read-only live installation check.

## Installed result

This Mac was first moved from the running `0.1.1-custom` legacy bundle to verified, published **v0.1.2**, including its existing login item. After regression testing, the fixed local build **0.1.3-dev** was installed at `/Applications/Codex Usage Status.app`.

- Installed architecture: arm64; strict signature verification passed.
- Existing `dev.local.CodexUsageStatus` LaunchAgent points to the canonical app. `RunAtLoad=true` and `KeepAlive=true` remain enabled; the existing `CODEX_BIN` setting was preserved.
- Exactly one monitor process was observed. Directly launching another copy exited 0 without creating a second monitor.
- Live `--once` read: **5H 27% remaining, 7D 89% remaining**. The menu-bar screenshot showed the same values. These are a dated verification snapshot, not guaranteed current readings.
- Both old installed bundles are recoverable under `/Applications/.CodexUsageStatus-migration-backup-20261018T005303Z-20032/`. The first pre-upgrade copy/configuration is also retained in the session's review backup directory.
- No public tag or release asset was changed. This is a local development build.

## Remaining verification limits

No known original application regression remains failing in the executed matrix. This is not proof that every possible bug is absent. Physical lid/sleep, long-duration battery/energy measurement, Intel/macOS 13 hardware, real cross-account switching, wallpaper/display permutations and hosted XCTest/CI execution were not performed. Simulated workspace notifications, bounded stress runs and cross-compilation are reported only for what they measure.
