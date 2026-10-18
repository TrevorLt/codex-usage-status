#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/scripts/fixtures/install-migration"
INSTALLER="$ROOT_DIR/scripts/install-macos-app.sh"
TEST_TMPDIR="${TMPDIR:-/tmp}"
TEST_TMPDIR="${TEST_TMPDIR%/}"
TEST_TMPDIR="$(cd -P "$TEST_TMPDIR" && pwd)"
TEST_ROOT="$(mktemp -d "$TEST_TMPDIR/codex-usage-status-install-test.XXXXXX")"
ORIGINAL_PATH="$PATH"
TEST_MODULE_CACHE="${CODEX_USAGE_TEST_MODULE_CACHE:-$TEST_ROOT/module-cache}"
mkdir -p "$TEST_MODULE_CACHE"

cleanup() {
  local status="$?"
  trap - EXIT
  case "$TEST_ROOT" in
    "$TEST_TMPDIR"/codex-usage-status-install-test.*)
      if [[ -d "$TEST_ROOT" && ! -L "$TEST_ROOT" ]]; then /bin/rm -R "$TEST_ROOT"; fi
      ;;
    *) printf 'Refusing to clean unexpected test path: %s\n' "$TEST_ROOT" >&2 ;;
  esac
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label (expected '$expected', got '$actual')"
}

assert_file_contains() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" ]] || fail "$label (missing file: $path)"
  /usr/bin/grep -Fq "$expected" "$path" || fail "$label (missing '$expected' in $path)"
}

assert_file_lacks() {
  local path="$1" forbidden="$2" label="$3"
  if [[ -f "$path" ]] && /usr/bin/grep -Fq "$forbidden" "$path"; then
    fail "$label (unexpected '$forbidden' in $path)"
  fi
}

case_init() {
  local name="$1"
  CASE_ROOT="$TEST_ROOT/$name"
  MOCK_BIN="$CASE_ROOT/bin"
  SOURCE_APP="$CASE_ROOT/source/Codex Usage Status.app"
  TARGET_PARENT="$CASE_ROOT/Applications"
  TARGET_APP="$TARGET_PARENT/Codex Usage Status.app"
  LEGACY_APP="$TARGET_PARENT/CodexUsageStatus.app"
  TARGET_EXECUTABLE="$TARGET_APP/Contents/MacOS/CodexUsageStatus"
  LEGACY_EXECUTABLE="$LEGACY_APP/Contents/MacOS/CodexUsageStatus"
  HOME="$CASE_ROOT/home"
  AGENT_PLIST="$HOME/Library/LaunchAgents/dev.local.CodexUsageStatus.plist"
  MOCK_LOG="$CASE_ROOT/commands.log"
  MOCK_LOADED_FILE="$CASE_ROOT/agent-state"
  MOCK_STARTED_EXECUTABLE_FILE="$CASE_ROOT/started-executable"
  MOCK_BOOTSTRAP_FAILED_FILE="$CASE_ROOT/bootstrap-failed-once"
  MOCK_STAGE_MOVE_FAILED_FILE="$CASE_ROOT/stage-move-failed-once"
  MOCK_AGENT_PLIST="$AGENT_PLIST"
  MOCK_SOURCE_APP="$SOURCE_APP"
  MOCK_TARGET_EXECUTABLE="$TARGET_EXECUTABLE"
  BUILD_SCRIPT="$FIXTURE_DIR/commands/build-macos-app.sh"
  export HOME BUILD_SCRIPT MOCK_LOG MOCK_LOADED_FILE MOCK_STARTED_EXECUTABLE_FILE
  export MOCK_BOOTSTRAP_FAILED_FILE MOCK_STAGE_MOVE_FAILED_FILE MOCK_AGENT_PLIST
  export MOCK_SOURCE_APP MOCK_TARGET_EXECUTABLE
  unset MOCK_BOOTSTRAP_FAIL_ONCE MOCK_FAIL_STAGE_MOVE_ONCE
  MOCK_OPEN_STATUS=0
  export MOCK_OPEN_STATUS
  PATH="$MOCK_BIN:$ORIGINAL_PATH"
  export PATH
  mkdir -p "$MOCK_BIN" "$SOURCE_APP/Contents/MacOS" "$TARGET_PARENT" "$HOME/Library/LaunchAgents"
  cp -R "$FIXTURE_DIR/commands/." "$MOCK_BIN/"
  cp -R "$FIXTURE_DIR/source-app/." "$SOURCE_APP/"
  chmod +x "$FIXTURE_DIR/commands/build-macos-app.sh" "$MOCK_BIN"/* "$SOURCE_APP/Contents/MacOS/CodexUsageStatus"
  : > "$MOCK_LOG"
}

install_agent_fixture() {
  mkdir -p "${AGENT_PLIST%/*}"
  cp "$FIXTURE_DIR/launch-agent.plist" "$AGENT_PLIST"
  /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 '$LEGACY_EXECUTABLE'" "$AGENT_PLIST"
}

install_previous_app() {
  local path="$1" marker="$2"
  cp -R "$SOURCE_APP" "$path"
  cp "$FIXTURE_DIR/$marker" "$path/Contents/Resources/version.txt"
}

run_installer_success() {
  if ! TARGET_APP="$TARGET_APP" "$INSTALLER" > "$CASE_ROOT/installer.out" 2> "$CASE_ROOT/installer.err"; then
    /bin/cat "$CASE_ROOT/installer.out" "$CASE_ROOT/installer.err" >&2
    fail "installer unexpectedly failed in $CASE_ROOT"
  fi
}

run_installer_failure() {
  if TARGET_APP="$TARGET_APP" "$INSTALLER" > "$CASE_ROOT/installer.out" 2> "$CASE_ROOT/installer.err"; then
    /bin/cat "$CASE_ROOT/installer.out" >&2
    fail "installer unexpectedly succeeded in $CASE_ROOT"
  fi
}

case_init loaded-migration
install_agent_fixture
printf 'loaded\n' > "$MOCK_LOADED_FILE"
install_previous_app "$LEGACY_APP" legacy-version.txt
install_previous_app "$TARGET_APP" target-version.txt
run_installer_success
assert_eq "$(<"$TARGET_APP/Contents/Resources/version.txt")" "new-version" "installed bundle content"
backup_root="$(find "$TARGET_PARENT" -mindepth 1 -maxdepth 1 -type d -name '.CodexUsageStatus-migration-backup-*' -print -quit)"
[[ -n "$backup_root" ]] || fail "successful migration did not preserve app backups"
assert_eq "$(<"$backup_root/CodexUsageStatus.app/Contents/Resources/version.txt")" "legacy-version" "legacy app backup"
assert_eq "$(<"$backup_root/Codex Usage Status.app/Contents/Resources/version.txt")" "previous-target-version" "previous target backup"
assert_eq "$(plutil -extract ProgramArguments.0 raw -o - "$AGENT_PLIST")" "$TARGET_EXECUTABLE" "migrated LaunchAgent executable"
assert_eq "$(plutil -extract ProgramArguments.1 raw -o - "$AGENT_PLIST")" "preserve-this-argument" "unrelated ProgramArguments entry"
assert_eq "$(plutil -extract KeepAlive raw -o - "$AGENT_PLIST")" "true" "KeepAlive setting"
assert_eq "$(plutil -extract RunAtLoad raw -o - "$AGENT_PLIST")" "true" "RunAtLoad setting"
assert_eq "$(plutil -extract EnvironmentVariables.CODEX_BIN raw -o - "$AGENT_PLIST")" "/custom/codex/bin" "CODEX_BIN setting"
plist_backup="$(find "${AGENT_PLIST%/*}" -maxdepth 1 -type f -name 'dev.local.CodexUsageStatus.plist.backup-*' -print -quit)"
[[ -n "$plist_backup" ]] || fail "successful migration did not preserve the original LaunchAgent plist"
assert_eq "$(plutil -extract ProgramArguments.0 raw -o - "$plist_backup")" "$LEGACY_EXECUTABLE" "LaunchAgent backup path"
assert_file_contains "$MOCK_LOG" "launchctl bootout gui/$(id -u) $AGENT_PLIST" "exact LaunchAgent bootout"
assert_file_lacks "$MOCK_LOG" "open " "no second launch after bootstrap"
bootout_line="$(awk '/^launchctl bootout / { print NR; exit }' "$MOCK_LOG")"
process_scan_line="$(awk '/^ps -axo / { print NR; exit }' "$MOCK_LOG")"
bootstrap_line="$(awk '/^launchctl bootstrap / { print NR; exit }' "$MOCK_LOG")"
[[ "$bootout_line" -lt "$process_scan_line" && "$process_scan_line" -lt "$bootstrap_line" ]] || fail "loaded agent ordering is incorrect"

case_init unloaded-agent
install_agent_fixture
printf 'unloaded\n' > "$MOCK_LOADED_FILE"
run_installer_success
assert_eq "$(plutil -extract ProgramArguments.0 raw -o - "$AGENT_PLIST")" "$TARGET_EXECUTABLE" "unloaded LaunchAgent path migration"
assert_file_lacks "$MOCK_LOG" "launchctl bootout " "unloaded agent must not be booted out"
assert_file_lacks "$MOCK_LOG" "launchctl bootstrap " "unloaded agent must not be enabled"
assert_file_contains "$MOCK_LOG" "open $TARGET_APP" "unloaded agent direct launch"

case_init failed-app-swap
install_agent_fixture
printf 'loaded\n' > "$MOCK_LOADED_FILE"
install_previous_app "$LEGACY_APP" legacy-version.txt
install_previous_app "$TARGET_APP" target-version.txt
MOCK_FAIL_STAGE_MOVE_ONCE=1
export MOCK_FAIL_STAGE_MOVE_ONCE
run_installer_failure
assert_eq "$(<"$TARGET_APP/Contents/Resources/version.txt")" "previous-target-version" "target restored after app swap failure"
assert_eq "$(<"$LEGACY_APP/Contents/Resources/version.txt")" "legacy-version" "legacy path restored after app swap failure"
assert_eq "$(plutil -extract ProgramArguments.0 raw -o - "$AGENT_PLIST")" "$LEGACY_EXECUTABLE" "LaunchAgent preserved after app swap failure"
assert_file_contains "$MOCK_LOG" "launchctl bootstrap gui/$(id -u) $AGENT_PLIST" "previous login state restored after app swap failure"

case_init failed-bootstrap
install_agent_fixture
printf 'loaded\n' > "$MOCK_LOADED_FILE"
install_previous_app "$TARGET_APP" target-version.txt
MOCK_BOOTSTRAP_FAIL_ONCE=1
export MOCK_BOOTSTRAP_FAIL_ONCE
run_installer_failure
assert_eq "$(<"$TARGET_APP/Contents/Resources/version.txt")" "previous-target-version" "target restored after bootstrap failure"
assert_eq "$(plutil -extract ProgramArguments.0 raw -o - "$AGENT_PLIST")" "$LEGACY_EXECUTABLE" "LaunchAgent restored after bootstrap failure"
failed_backup="$(find "$TARGET_PARENT" -path '*/failed-install.app/Contents/Resources/version.txt' -print -quit)"
assert_eq "$(<"$failed_backup")" "new-version" "failed new app retained for recovery"
assert_eq "$(<"$MOCK_LOADED_FILE")" "loaded" "prior loaded state restored after bootstrap failure"

case_init fresh-open-failure
MOCK_OPEN_STATUS=1
export MOCK_OPEN_STATUS
run_installer_failure
[[ ! -e "$TARGET_APP" ]] || fail "fresh install rollback left a new app at TARGET_APP"
failed_backup="$(find "$TARGET_PARENT" -path '*/failed-install.app/Contents/Resources/version.txt' -print -quit)"
[[ -n "$failed_backup" ]] || fail "fresh install rollback did not retain the failed bundle"
assert_eq "$(<"$failed_backup")" "new-version" "fresh install failed bundle backup"
assert_file_lacks "$MOCK_LOG" "launchctl " "fresh install must not create or enable a login item"

case_init arbitrary-target
mkdir -p "$TARGET_APP"
printf 'leave-me-alone\n' > "$TARGET_APP/marker.txt"
run_installer_failure
assert_eq "$(<"$TARGET_APP/marker.txt")" "leave-me-alone" "unrelated target must remain untouched"
assert_file_lacks "$MOCK_LOG" "launchctl " "invalid target must fail before service operations"

case_init instance-guard
mkdir -p "$CASE_ROOT/guard"
swiftc -swift-version 6 \
  -module-cache-path "$TEST_MODULE_CACHE" \
  "$ROOT_DIR/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/ApplicationInstanceGuard.swift" \
  "$FIXTURE_DIR/application-instance-guard-harness.swift" \
  -o "$CASE_ROOT/application-instance-guard-test"
"$CASE_ROOT/application-instance-guard-test" "$CASE_ROOT/guard/instance.lock" > "$CASE_ROOT/guard.out"
assert_eq "$(<"$CASE_ROOT/guard.out")" "APPLICATION INSTANCE GUARD PASS" "cross-process singleton contention"

case_init once-bypass
APP_SOURCE_DIR="$ROOT_DIR/macos/CodexUsageStatus/Sources/CodexUsageStatus"
once_line="$(awk '/CommandLine.arguments.contains\("--once"\)/ { print NR; exit }' "$APP_SOURCE_DIR/main.swift")"
guard_line="$(awk '/ApplicationInstanceGuard.acquireForCurrentUser/ { print NR; exit }' "$APP_SOURCE_DIR/main.swift")"
[[ -n "$once_line" && -n "$guard_line" && "$once_line" -lt "$guard_line" ]] || fail "--once must branch before instance-guard acquisition"
swiftc -swift-version 6 -O \
  -module-cache-path "$TEST_MODULE_CACHE" \
  "$APP_SOURCE_DIR/App/"*.swift \
  "$APP_SOURCE_DIR/Codex/"*.swift \
  "$APP_SOURCE_DIR/Domain/"*.swift \
  "$APP_SOURCE_DIR/UI/"*.swift \
  "$APP_SOURCE_DIR/main.swift" \
  -o "$CASE_ROOT/CodexUsageStatus"
cp "$FIXTURE_DIR/commands/fake-codex" "$CASE_ROOT/fake-codex"
chmod +x "$CASE_ROOT/fake-codex"
once_output="$(HOME="$HOME" CODEX_BIN="$CASE_ROOT/fake-codex" "$CASE_ROOT/CodexUsageStatus" --once)"
assert_eq "$once_output" "5h 65% 7d 88%" "--once output and guard bypass"

printf 'INSTALL MIGRATION PASS\n'
