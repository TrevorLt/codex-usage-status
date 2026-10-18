#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_TARGET_APP="/Applications/Codex Usage Status.app"
TARGET_APP="${TARGET_APP:-$DEFAULT_TARGET_APP}"
BUILD_SCRIPT="${BUILD_SCRIPT:-$ROOT_DIR/scripts/build-macos-app.sh}"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"
APP_BUNDLE_ID="dev.local.CodexUsageStatus"
APP_EXECUTABLE="CodexUsageStatus"
LAUNCH_AGENT_LABEL="dev.local.CodexUsageStatus"

die() {
  printf 'Install failed: %s\n' "$*" >&2
  exit 1
}

contains_parent_segment() {
  case "/$1/" in
    */../*) return 0 ;;
    *) return 1 ;;
  esac
}

app_is_ours() {
  local app_path="$1"
  [[ -d "$app_path" && ! -L "$app_path" ]] || return 1
  [[ -f "$app_path/Contents/Info.plist" && -x "$app_path/Contents/MacOS/$APP_EXECUTABLE" ]] || return 1
  [[ "$(plutil -extract CFBundleIdentifier raw -o - "$app_path/Contents/Info.plist" 2>/dev/null)" == "$APP_BUNDLE_ID" ]] || return 1
  [[ "$(plutil -extract CFBundleExecutable raw -o - "$app_path/Contents/Info.plist" 2>/dev/null)" == "$APP_EXECUTABLE" ]]
}

if [[ "$TARGET_APP" != /* ]] || contains_parent_segment "$TARGET_APP"; then
  die "TARGET_APP must be an absolute path without '..' components."
fi
[[ "${TARGET_APP##*/}" == *.app && "${TARGET_APP##*/}" != ".app" ]] || die "TARGET_APP must name an .app bundle."
case "$TARGET_APP" in
  *"'"*|*$'\n'*) die "TARGET_APP cannot contain a quote or newline because the plist editor uses a quoted command value." ;;
esac
TARGET_BASENAME="${TARGET_APP##*/}"
TARGET_INPUT_PARENT="${TARGET_APP%/*}"
[[ -n "$TARGET_INPUT_PARENT" ]] || TARGET_INPUT_PARENT="/"
[[ -d "$TARGET_INPUT_PARENT" ]] || die "TARGET_APP parent directory does not exist: $TARGET_INPUT_PARENT"
TARGET_PARENT="$(cd -P "$TARGET_INPUT_PARENT" && pwd)"
TARGET_APP="$TARGET_PARENT/$TARGET_BASENAME"
[[ "$TARGET_APP" != "$ROOT_DIR/dist/Codex Usage Status.app" ]] || die "TARGET_APP cannot be the build output bundle."
[[ ! -L "$TARGET_APP" ]] || die "Refusing to replace a symbolic-link TARGET_APP: $TARGET_APP"

# The legacy bundle is resolved beside the selected destination. This keeps an
# override entirely inside its chosen install tree and avoids touching the
# default /Applications installation when testing or using a custom target.
LEGACY_APP="$TARGET_PARENT/CodexUsageStatus.app"
LEGACY_EXECUTABLE="$LEGACY_APP/Contents/MacOS/$APP_EXECUTABLE"
TARGET_EXECUTABLE="$TARGET_APP/Contents/MacOS/$APP_EXECUTABLE"

[[ -x "$BUILD_SCRIPT" && -f "$BUILD_SCRIPT" ]] || die "Build script is missing or not executable: $BUILD_SCRIPT"
BUILD_OUTPUT="$("$BUILD_SCRIPT")" || die "Application build failed."
[[ -n "$BUILD_OUTPUT" && "$BUILD_OUTPUT" != *$'\n'* ]] || die "Build script must return one app bundle path."
SOURCE_APP="$BUILD_OUTPUT"
app_is_ours "$SOURCE_APP" || die "Build script returned an invalid Codex Usage Status app bundle: $SOURCE_APP"
[[ "$SOURCE_APP" != "$TARGET_APP" && "$SOURCE_APP" != "$LEGACY_APP" ]] || die "Build output cannot be an installation target."

if [[ -e "$TARGET_APP" ]]; then
  app_is_ours "$TARGET_APP" || die "Refusing to replace a target that is not this app: $TARGET_APP"
fi
if [[ "$LEGACY_APP" != "$TARGET_APP" && -e "$LEGACY_APP" ]]; then
  app_is_ours "$LEGACY_APP" || die "Refusing to migrate a legacy path that is not this app: $LEGACY_APP"
fi

[[ "${HOME:-}" == /* ]] || die "HOME must be set to an absolute path."
AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
AGENT_DOMAIN="gui/$(id -u)"
AGENT_EXISTS=0
AGENT_WAS_LOADED=0
AGENT_BOOTED_OUT=0
AGENT_BOOTSTRAPPED=0
AGENT_PLIST_UPDATED=0
AGENT_PLIST_BACKUP=""
AGENT_PLIST_TEMP=""

if [[ -L "$AGENT_PLIST" ]]; then
  die "Refusing to follow a symbolic-link LaunchAgent plist: $AGENT_PLIST"
fi
if [[ -e "$AGENT_PLIST" ]]; then
  AGENT_EXISTS=1
  [[ -x "$PLISTBUDDY" ]] || die "PlistBuddy is unavailable; cannot preserve the LaunchAgent safely."
  plutil -lint "$AGENT_PLIST" >/dev/null || die "LaunchAgent plist is invalid: $AGENT_PLIST"
  [[ "$("$PLISTBUDDY" -c 'Print :Label' "$AGENT_PLIST")" == "$LAUNCH_AGENT_LABEL" ]] || die "Unexpected Label in LaunchAgent plist: $AGENT_PLIST"
  CURRENT_AGENT_EXECUTABLE="$("$PLISTBUDDY" -c 'Print :ProgramArguments:0' "$AGENT_PLIST")" || die "LaunchAgent has no ProgramArguments[0]: $AGENT_PLIST"
  DEFAULT_LEGACY_EXECUTABLE="/Applications/CodexUsageStatus.app/Contents/MacOS/$APP_EXECUTABLE"
  DEFAULT_SPACED_EXECUTABLE="/Applications/Codex Usage Status.app/Contents/MacOS/$APP_EXECUTABLE"
  case "$CURRENT_AGENT_EXECUTABLE" in
    "$LEGACY_EXECUTABLE"|"$TARGET_EXECUTABLE"|"$DEFAULT_LEGACY_EXECUTABLE"|"$DEFAULT_SPACED_EXECUTABLE") ;;
    *) die "LaunchAgent executable is outside the known app paths; leaving it untouched: $CURRENT_AGENT_EXECUTABLE (legacy: $LEGACY_EXECUTABLE; target: $TARGET_EXECUTABLE)" ;;
  esac

  command -v launchctl >/dev/null 2>&1 || die "launchctl is unavailable; cannot preserve the LaunchAgent's loaded state."
  AGENT_LIST="$(launchctl list)" || die "Unable to inspect the current LaunchAgent state."
  if printf '%s\n' "$AGENT_LIST" | awk -v label="$LAUNCH_AGENT_LABEL" '$NF == label { found = 1 } END { exit !found }'; then
    AGENT_WAS_LOADED=1
  fi
fi

STAGE_ROOT="$(mktemp -d "$TARGET_PARENT/.codex-usage-status-stage.XXXXXX")" || die "Unable to create a staging directory beside TARGET_APP."
STAGED_APP="$STAGE_ROOT/Codex Usage Status.app"
ditto "$SOURCE_APP" "$STAGED_APP" || die "Unable to stage the built application."
app_is_ours "$STAGED_APP" || die "Staged application failed identity checks."

BACKUP_ROOT=""
TARGET_BACKUP=""
LEGACY_BACKUP=""
TARGET_MOVED=0
LEGACY_MOVED=0
NEW_TARGET_INSTALLED=0

create_backup_root() {
  [[ -n "$BACKUP_ROOT" ]] && return 0
  local stamp candidate suffix=0
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  candidate="$TARGET_PARENT/.CodexUsageStatus-migration-backup-$stamp-$$"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    suffix=$((suffix + 1))
    candidate="$TARGET_PARENT/.CodexUsageStatus-migration-backup-$stamp-$$-$suffix"
  done
  mkdir -m 700 "$candidate" || die "Unable to create a recoverable backup directory."
  BACKUP_ROOT="$candidate"
}

move_to_backup() {
  local app_path="$1" backup_path="$2"
  [[ ! -e "$backup_path" && ! -L "$backup_path" ]] || die "Backup destination already exists: $backup_path"
  mv "$app_path" "$backup_path" || die "Unable to move existing app into its recoverable backup: $app_path"
}

remove_plist_temp() {
  if [[ -n "$AGENT_PLIST_TEMP" && -f "$AGENT_PLIST_TEMP" && ! -L "$AGENT_PLIST_TEMP" ]]; then
    rm -f "$AGENT_PLIST_TEMP"
  fi
  AGENT_PLIST_TEMP=""
}

restore_agent_plist() {
  [[ "$AGENT_PLIST_UPDATED" == 1 && -n "$AGENT_PLIST_BACKUP" ]] || return 0
  local restore_temp
  restore_temp="$(mktemp "${AGENT_PLIST%/*}/.$LAUNCH_AGENT_LABEL.restore.XXXXXX")" || return 1
  cp -p "$AGENT_PLIST_BACKUP" "$restore_temp" || return 1
  mv "$restore_temp" "$AGENT_PLIST" || return 1
  AGENT_PLIST_UPDATED=0
}

matching_process_pids() {
  local executable="$1"
  ps -axo pid=,stat=,command= | awk -v executable="$executable" '
    {
      pid = $1
      state = $2
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", $0)
      command = $0
      if (state !~ /^Z/ && (command == executable || index(command, executable " ") == 1)) print pid
    }
  '
}

pid_matches_executable() {
  local pid="$1" executable="$2" process_record state command
  process_record="$(ps -p "$pid" -o stat=,command= 2>/dev/null)" || return 1
  [[ -n "$process_record" ]] || return 1
  state="${process_record%%[[:space:]]*}"
  [[ "$state" != Z* ]] || return 1
  command="${process_record#"$state"}"
  command="${command#"${command%%[![:space:]]*}"}"
  [[ "$command" == "$executable" || "$command" == "$executable "* ]]
}

wait_for_process_exit() {
  local executable="$1" pids="$2" attempt pid alive
  for ((attempt = 0; attempt < 30; attempt++)); do
    alive=0
    while IFS= read -r pid; do
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      if pid_matches_executable "$pid" "$executable"; then alive=1; fi
    done <<< "$pids"
    [[ "$alive" == 0 ]] && return 0
    sleep 0.1
  done

  # TERM gets three seconds. Escalate only after re-reading each PID's exact
  # command line, then wait another two seconds before rolling back.
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if pid_matches_executable "$pid" "$executable"; then
      kill -KILL "$pid" 2>/dev/null || {
        pid_matches_executable "$pid" "$executable" && return 1
      }
    fi
  done <<< "$pids"

  for ((attempt = 0; attempt < 20; attempt++)); do
    alive=0
    while IFS= read -r pid; do
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      if pid_matches_executable "$pid" "$executable"; then alive=1; fi
    done <<< "$pids"
    [[ "$alive" == 0 ]] && return 0
    sleep 0.1
  done
  return 1
}

stop_targeted_processes() {
  local executable="$1" pids pid
  pids="$(matching_process_pids "$executable")" || die "Unable to inspect processes for $executable"
  [[ -n "$pids" ]] || return 0
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if pid_matches_executable "$pid" "$executable"; then
      kill -TERM "$pid" 2>/dev/null || {
        pid_matches_executable "$pid" "$executable" && die "Unable to send TERM to targeted process $pid."
      }
    fi
  done <<< "$pids"
  wait_for_process_exit "$executable" "$pids" || die "Targeted process for $executable remained alive after bounded TERM/KILL escalation."
}

wait_for_target_process() {
  local executable="$1" attempt pids
  for ((attempt = 0; attempt < 50; attempt++)); do
    pids="$(matching_process_pids "$executable")" || die "Unable to verify the running app process."
    [[ -n "$pids" ]] && return 0
    sleep 0.1
  done
  die "The installed app did not appear as a running process: $executable"
}

rollback_install() {
  local original_status="$?"
  trap - EXIT
  set +e
  printf 'Install failed; restoring the prior app and LaunchAgent state.\n' >&2

  if [[ "$AGENT_BOOTSTRAPPED" == 1 ]]; then
    launchctl bootout "$AGENT_DOMAIN" "$AGENT_PLIST" >/dev/null 2>&1
    AGENT_BOOTSTRAPPED=0
  fi
  restore_agent_plist

  if [[ "$NEW_TARGET_INSTALLED" == 1 && -e "$TARGET_APP" ]]; then
    if [[ -z "$BACKUP_ROOT" ]]; then
      local stamp candidate suffix=0
      stamp="$(date -u +%Y%m%dT%H%M%SZ)"
      candidate="$TARGET_PARENT/.CodexUsageStatus-migration-backup-$stamp-$$"
      while [[ -e "$candidate" || -L "$candidate" ]]; do
        suffix=$((suffix + 1))
        candidate="$TARGET_PARENT/.CodexUsageStatus-migration-backup-$stamp-$$-$suffix"
      done
      if mkdir -m 700 "$candidate"; then BACKUP_ROOT="$candidate"; fi
    fi
  fi
  if [[ "$NEW_TARGET_INSTALLED" == 1 && -e "$TARGET_APP" && -n "$BACKUP_ROOT" ]]; then
    local failed_install="$BACKUP_ROOT/failed-install.app"
    if [[ ! -e "$failed_install" && ! -L "$failed_install" ]]; then
      mv "$TARGET_APP" "$failed_install"
    fi
  fi
  if [[ "$TARGET_MOVED" == 1 && -n "$TARGET_BACKUP" && -e "$TARGET_BACKUP" && ! -e "$TARGET_APP" ]]; then
    mv "$TARGET_BACKUP" "$TARGET_APP"
  fi
  if [[ "$LEGACY_MOVED" == 1 && -n "$LEGACY_BACKUP" && -e "$LEGACY_BACKUP" && ! -e "$LEGACY_APP" ]]; then
    mv "$LEGACY_BACKUP" "$LEGACY_APP"
  fi

  if [[ "$AGENT_WAS_LOADED" == 1 && "$AGENT_BOOTED_OUT" == 1 && "$AGENT_EXISTS" == 1 ]]; then
    launchctl bootstrap "$AGENT_DOMAIN" "$AGENT_PLIST" >/dev/null 2>&1
  fi
  remove_plist_temp
  printf 'Recovery copies, if needed, are under: %s\n' "${BACKUP_ROOT:-$STAGE_ROOT}" >&2
  exit "$original_status"
}
trap rollback_install EXIT

if [[ "$AGENT_WAS_LOADED" == 1 ]]; then
  launchctl bootout "$AGENT_DOMAIN" "$AGENT_PLIST" || die "Unable to unload the existing LaunchAgent."
  AGENT_BOOTED_OUT=1
fi

 # Stop only the two app executables adjacent to the selected target. Matching
 # compares literal command-line text, never a regex or a process name alone.
stop_targeted_processes "$LEGACY_EXECUTABLE"
if [[ "$TARGET_EXECUTABLE" != "$LEGACY_EXECUTABLE" ]]; then
  stop_targeted_processes "$TARGET_EXECUTABLE"
fi

if [[ -e "$TARGET_APP" ]]; then
  create_backup_root
  TARGET_BACKUP="$BACKUP_ROOT/${TARGET_APP##*/}"
  move_to_backup "$TARGET_APP" "$TARGET_BACKUP"
  TARGET_MOVED=1
fi
if [[ "$LEGACY_APP" != "$TARGET_APP" && -e "$LEGACY_APP" ]]; then
  create_backup_root
  LEGACY_BACKUP="$BACKUP_ROOT/${LEGACY_APP##*/}"
  move_to_backup "$LEGACY_APP" "$LEGACY_BACKUP"
  LEGACY_MOVED=1
fi

mv "$STAGED_APP" "$TARGET_APP" || die "Unable to install the staged app at $TARGET_APP"
NEW_TARGET_INSTALLED=1

if [[ "$AGENT_EXISTS" == 1 && "$CURRENT_AGENT_EXECUTABLE" != "$TARGET_EXECUTABLE" ]]; then
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  AGENT_PLIST_BACKUP="$AGENT_PLIST.backup-$stamp-$$"
  suffix=0
  while [[ -e "$AGENT_PLIST_BACKUP" || -L "$AGENT_PLIST_BACKUP" ]]; do
    suffix=$((suffix + 1))
    AGENT_PLIST_BACKUP="$AGENT_PLIST.backup-$stamp-$$-$suffix"
  done
  cp -p "$AGENT_PLIST" "$AGENT_PLIST_BACKUP" || die "Unable to create a recoverable LaunchAgent backup."
  AGENT_PLIST_TEMP="$(mktemp "${AGENT_PLIST%/*}/.$LAUNCH_AGENT_LABEL.update.XXXXXX")" || die "Unable to stage the LaunchAgent update."
  cp -p "$AGENT_PLIST" "$AGENT_PLIST_TEMP" || die "Unable to copy the LaunchAgent for an atomic update."
  "$PLISTBUDDY" -c "Set :ProgramArguments:0 '$TARGET_EXECUTABLE'" "$AGENT_PLIST_TEMP" || die "Unable to update LaunchAgent ProgramArguments[0]."
  plutil -lint "$AGENT_PLIST_TEMP" >/dev/null || die "Updated LaunchAgent plist failed validation."
  [[ "$("$PLISTBUDDY" -c 'Print :ProgramArguments:0' "$AGENT_PLIST_TEMP")" == "$TARGET_EXECUTABLE" ]] || die "Updated LaunchAgent executable did not round-trip correctly."
  mv "$AGENT_PLIST_TEMP" "$AGENT_PLIST" || die "Unable to atomically install the updated LaunchAgent plist."
  AGENT_PLIST_TEMP=""
  AGENT_PLIST_UPDATED=1
fi

if [[ "$AGENT_WAS_LOADED" == 1 ]]; then
  launchctl bootstrap "$AGENT_DOMAIN" "$AGENT_PLIST" || die "Unable to reload the existing LaunchAgent."
  AGENT_BOOTSTRAPPED=1
else
  open "$TARGET_APP" || die "The app was installed, but macOS could not open it."
fi

wait_for_target_process "$TARGET_EXECUTABLE"
trap - EXIT
rmdir "$STAGE_ROOT" 2>/dev/null || true

printf 'Installed and started %s\n' "$TARGET_APP"
if [[ -n "$BACKUP_ROOT" ]]; then
  printf 'Previous app bundle(s) are recoverable at %s\n' "$BACKUP_ROOT"
fi
if [[ -n "$AGENT_PLIST_BACKUP" ]]; then
  printf 'Previous LaunchAgent plist is recoverable at %s\n' "$AGENT_PLIST_BACKUP"
fi
if [[ "$AGENT_WAS_LOADED" != 1 ]]; then
  printf 'The app was not loaded as a login item; no login item was enabled.\n'
fi
