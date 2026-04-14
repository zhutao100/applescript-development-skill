#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/compile.sh"

if [[ ! -f "$ROOT_DIR/build/cli.scpt" ]]; then
  "$BUILD_SCRIPT"
fi

# Pass all args through to the AppleScript run handler.
/usr/bin/osascript -s s "$ROOT_DIR/build/cli.scpt" "$@"
