#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Create a bundled AppleScript applet (.app) from a .applescript source.

Usage:
  create_applet.sh --src <script.applescript> --out <applet.app> [--stay-open] [--startup-screen] [--execute-only]

Notes:
- A .app output gives a stable bundle identity (useful for consistent TCC Automation approvals).
- Passing CLI arguments to applets is not the same as osascript argv; design applets accordingly.

Example:
  create_applet.sh --src ./src/cli.applescript --out ./build/AutomationRunner.app
USAGE
}

SRC=""
OUT=""
STAY_OPEN=0
STARTUP_SCREEN=0
EXECUTE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)
      SRC="${2:-}"
      shift 2
      ;;
    --out)
      OUT="${2:-}"
      shift 2
      ;;
    --stay-open)
      STAY_OPEN=1
      shift
      ;;
    --startup-screen)
      STARTUP_SCREEN=1
      shift
      ;;
    --execute-only)
      EXECUTE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac

done

if [[ -z "$SRC" || -z "$OUT" ]]; then
  echo "--src and --out are required" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$SRC" ]]; then
  echo "Source script not found: $SRC" >&2
  exit 1
fi

if [[ "$OUT" != *.app ]]; then
  echo "Output must end with .app: $OUT" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"

args=(/usr/bin/osacompile -o "$OUT")

if [[ $EXECUTE_ONLY -eq 1 ]]; then
  args+=(-x)
fi
if [[ $STAY_OPEN -eq 1 ]]; then
  args+=(-s)
fi
if [[ $STARTUP_SCREEN -eq 1 ]]; then
  args+=(-u)
fi

args+=("$SRC")

"${args[@]}"

echo "Created applet: $OUT"
