#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_base="${RUNNER_TEMP:-${TMPDIR:-/private/tmp}}"
log_dir="$(mktemp -d "${log_base%/}/codex-usage-native.XXXXXX")"
export CODEX_USAGE_TEST_MODULE_CACHE="$log_dir/module-cache"
mkdir -p "$CODEX_USAGE_TEST_MODULE_CACHE"
failures=0

run_harness() {
  local name="$1"
  local script_name="$2"
  local marker_pattern="$3"
  local gui_required="${4:-false}"
  local script_path="$project_root/scripts/$script_name"
  local log_path="$log_dir/$name.log"
  local status=0
  local marker_count

  printf '\n=== Native harness: %s ===\n' "$name"
  if [[ ! -f "$script_path" ]]; then
    printf 'FAIL: required harness script is missing: %s\n' "$script_path" | tee "$log_path"
    failures=$((failures + 1))
    return
  fi

  bash "$script_path" >"$log_path" 2>&1 || status=$?
  cat "$log_path"

  if [[ "$status" -ne 0 ]]; then
    if [[ "$gui_required" == true ]]; then
      printf 'FAIL: %s exited with status %s; GUI/WindowServer access may be unavailable. This harness was not skipped. Log: %s\n' "$name" "$status" "$log_path" >&2
    else
      printf 'FAIL: %s exited with status %s; log: %s\n' "$name" "$status" "$log_path" >&2
    fi
    failures=$((failures + 1))
    return
  fi

  marker_count="$(grep -E -c -- "$marker_pattern" "$log_path" || true)"
  if [[ "$marker_count" != 1 ]]; then
    if [[ "$gui_required" == true ]]; then
      printf 'FAIL: %s exited 0 but did not emit exactly one required PASS marker. GUI/WindowServer access may be unavailable; this harness was not skipped. Log: %s\n' "$name" "$log_path" >&2
    else
      printf 'FAIL: %s exited 0 but did not emit exactly one required PASS marker. Log: %s\n' "$name" "$log_path" >&2
    fi
    failures=$((failures + 1))
    return
  fi

  printf 'Verified harness marker: %s\n' "$name"
}

printf 'Native test logs: %s\n' "$log_dir"

run_harness 'policy-domain' 'test-policy-domain.sh' '^POLICY DOMAIN PASS([[:space:]]|$)'
run_harness 'path-resolution' 'test-codex-path-resolution.sh' '^PATH RESOLVER PASS$'
run_harness 'fetcher-lifecycle' 'test-fetcher-lifecycle.sh' '^FETCHER LIFECYCLE PASS$'
run_harness 'native-faults' 'test-native-faults.sh' '^NATIVE FAULTS PASS([[:space:]]|$)'
run_harness 'install-migration' 'test-install-migration.sh' '^INSTALL MIGRATION PASS([[:space:]:]|$)'
run_harness 'wake-recovery' 'test-wake-recovery.sh' '^WAKE RECOVERY INTEGRATION PASS([[:space:]]|$)' true
run_harness 'badge-rendering' 'test-badge-rendering.sh' '^BADGE RENDERING PASS([[:space:]:]|$)' true

if [[ "$failures" -ne 0 ]]; then
  printf '\nNative test suite failed: %s harness(es); logs: %s\n' "$failures" "$log_dir" >&2
  exit 1
fi

printf '\nNATIVE TEST SUITE PASS (7 harnesses; logs: %s)\n' "$log_dir"
