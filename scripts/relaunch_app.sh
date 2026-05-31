#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/PulseBar.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "PulseBar is not installed at $APP_PATH" >&2
    echo "Run ./scripts/package_app.sh first." >&2
    exit 1
fi

pkill -x PulseBar 2>/dev/null || true
sleep 1
open "$APP_PATH"
