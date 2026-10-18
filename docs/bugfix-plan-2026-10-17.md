# Reliability repair plan — 2026-10-17

Baseline: `v0.1.2` / `b4ad618`. Findings and pre-fix reproducers are in the session's `review/2026-10-17/REVIEW.md`.

## Sequence and ownership

| Stage | Owner | Scope | Acceptance |
|---|---|---|---|
| 1. Upgrade this Mac | Main | Verify latest published release and checksum; back up old installation; migrate existing LaunchAgent to the spaced app name | Running v0.1.2 at the canonical path; one monitor; launch at login retained |
| 2. Native transport | Ampere, 6-luna xhigh | N1–N3: malformed RPC result, stderr backpressure, split UTF-8, bounded buffers and process cleanup | Original fault reproducers pass; real subprocess integration tests cover success, errors, hangs and shutdown |
| 3. CLI | Bernoulli, 6-luna xhigh | C1–C6 plus bounded, efficient diagnostic processing | Missing values are never full quota; correct windows/rounding; safe errors and discovery; no timer/process leaks |
| 4. Menu-bar rendering | Pasteur, 6-luna xhigh | N4: visible 0% warning; native neutral contrast while warning overlays remain red | 0/19% warning, 20% neutral, both styles; native tint survives mixed warning/normal data |
| 5. Upgrade and singleton | Noether, 6-luna xhigh | Exact login-agent migration, old bundle name, recoverable replacement, per-user single instance | Isolated installer failure/migration tests; direct and login launches cannot duplicate the monitor |
| 6. Test gates | Ptolemy, 6-luna xhigh | Native/domain runner, PASS markers, CI and release workflow gates | No exit-code-only false passes; native tests precede packaging |
| 7. Toolchain and integration | Main | Diagnose SwiftPM cache/API mismatch, integrate renderer hooks, README/release notes, full regression, local fixed build | All confirmed regressions green or explicitly unresolved; signed local build displays live usage and starts at login |

Workers have disjoint write scopes. Main reviews their patches and owns the final integration. No new project dependencies are needed.

## Validation contract

- Retain the audit's independent failing tests rather than changing their expected outcomes to fit a patch.
- Add targeted regression tests in the repository so fixes survive subsequent changes.
- Test policy/domain data without an account; use fake subprocess servers for failure, stream, and cleanup cases.
- Run AppKit assertions with WindowServer access and require an explicit PASS marker.
- Check both architectures compile and app signatures verify; distinguish this from Intel/macOS 13 hardware testing.
- Preserve the 30/60/120-second success cadence and 300-second failure backoff.
- Finish with one read-only real usage query, one running installed monitor, and the existing login-enabled state preserved.
- Physical sleep/lid, extended energy measurement, old macOS hardware and remote CI execution remain separate from simulated checks.

## Local upgrade record

Status: implementation and local validation completed. See [the verification record](bugfix-verification-2026-10-17.md) for results and explicit test-environment limits.

Latest published tag was verified as `v0.1.2`. The Apple Silicon ZIP SHA256 and the installed spaced-name binary match the release artifact. The original v0.1.1-custom app and LaunchAgent were backed up under the session's `review/2026-10-17/backups/before-upgrade/`. The exact existing LaunchAgent was unloaded, its executable path changed to `/Applications/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus`, and it was reloaded with KeepAlive and CODEX_BIN preserved. A live `--once` query succeeded.

The eventual patched local build will use a development version identifier until a new public release is requested. Public release assets are not replaced as part of this local repair.
