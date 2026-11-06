#!/bin/bash
# Build first so a failed build leaves the running app alone, then restart the dev build.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Build/Products/Debug/Glimpse.app"
scripts/build.sh >/dev/null
DEV_PATTERN="/build/Build/Products/Debug/Glimpse.app/" # dev builds only
pkill -f "$DEV_PATTERN" || true
# Wait for the old instance to exit; otherwise `open` may just re-activate the dying process.
while pgrep -f "$DEV_PATTERN" >/dev/null; do sleep 0.1; done
open "$APP"
