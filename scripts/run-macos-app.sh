#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Codex Usage Status.app"

if [[ ! -d "$APP_DIR" ]]; then
  "$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null
fi

pkill -x CodexUsageStatus 2>/dev/null || true
open -n "$APP_DIR"
echo "Started $APP_DIR"
