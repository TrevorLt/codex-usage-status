#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Codex Usage Status.app"
APP_BINARY="$APP_DIR/Contents/MacOS/CodexUsageStatus"
NATIVE_ARCH="$(uname -m)"
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then
  NATIVE_ARCH=arm64
fi

if ! lipo -verify_arch "$NATIVE_ARCH" "$APP_BINARY" >/dev/null 2>&1; then
  BUILD_ARCH="$NATIVE_ARCH" "$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null
fi
lipo -verify_arch "$NATIVE_ARCH" "$APP_BINARY" >/dev/null 2>&1 || {
  echo "App does not contain native $NATIVE_ARCH code; leaving the running app untouched." >&2
  exit 1
}

matching_process_pids() {
  local snapshot pid state command
  snapshot="$(ps -axww -o pid=,stat=,command=)" || return 1
  while read -r pid state command; do
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$state" != Z* && "$command" == "$1" ]] && printf '%s\n' "$pid"
  done <<< "$snapshot"
  return 0
}

wait_for_exit() {
  local pid="$1" attempt state
  for ((attempt = 0; attempt < 50; attempt++)); do
    state="$(ps -p "$pid" -o stat= 2>/dev/null)" || return 0
    read -r state <<< "$state"
    [[ -z "$state" || "$state" == Z* ]] && return 0
    sleep 0.1
  done
  echo "Process $pid did not stop; refusing to start a competing copy." >&2
  return 1
}

AGENT_DOMAIN="gui/$(id -u)"
AGENT_LABEL=dev.local.CodexUsageStatus
AGENT_PLIST=""
AGENT_STOPPED=0
restore_agent_on_failure() {
  local status="$?"
  trap - EXIT
  if [[ "$status" != 0 && "$AGENT_STOPPED" == 1 ]]; then
    launchctl bootstrap "$AGENT_DOMAIN" "$AGENT_PLIST" || echo "Could not restore the previous login task." >&2
  fi
  exit "$status"
}
trap restore_agent_on_failure EXIT

agent_pid="$(launchctl list | awk -v label="$AGENT_LABEL" '$NF == label { print $1; exit }')"
if [[ -n "$agent_pid" ]]; then
  AGENT_PLIST="$(launchctl print "$AGENT_DOMAIN/$AGENT_LABEL" | awk '/^[[:space:]]*path = / { sub(/^[[:space:]]*path = /, ""); print; exit }')"
  [[ -f "$AGENT_PLIST" ]] || { echo "Login task has no restorable plist; leaving it running." >&2; exit 1; }
  launchctl bootout "$AGENT_DOMAIN/$AGENT_LABEL"
  AGENT_STOPPED=1
  if [[ "$agent_pid" =~ ^[0-9]+$ ]]; then wait_for_exit "$agent_pid"; fi
fi

for executable in "$APP_BINARY" \
  '/Applications/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus' \
  '/Applications/CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus' \
  "$HOME/Applications/Codex Usage Status.app/Contents/MacOS/CodexUsageStatus"; do
  pids="$(matching_process_pids "$executable")"
  for pid in $pids; do
    current_pids="$(matching_process_pids "$executable")"
    if grep -Fxq "$pid" <<< "$current_pids"; then
      kill -TERM "$pid"
      wait_for_exit "$pid"
    fi
  done
done

open -n "$APP_DIR"
for ((attempt = 0; attempt < 50; attempt++)); do
  pids="$(matching_process_pids "$APP_BINARY")"
  if [[ -n "$pids" ]]; then
    trap - EXIT
    echo "Started $APP_DIR (PID $pids)"
    exit 0
  fi
  sleep 0.1
done
echo "The requested app did not stay running: $APP_BINARY" >&2
exit 1
