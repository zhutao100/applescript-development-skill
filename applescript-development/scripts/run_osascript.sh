#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run an AppleScript (or other OSA language) script via osascript with deterministic output options.

Usage:
  run_osascript.sh --script <path> [--language AppleScript] [--style h|s] [--errors-to stderr|stdout] -- [args...]

Examples:
  run_osascript.sh --script ./build/cli.scpt --style s -- arg1 arg2
  run_osascript.sh --script ./src/foo.applescript --language AppleScript --style s --

Notes:
- --style s uses recompilable source form output (unambiguous for lists/records).
- --errors-to stdout routes script errors to stdout (useful for golden error tests).
USAGE
}

SCRIPT=""
LANG="AppleScript"
STYLE="h"
ERRORS_TO="stderr"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --script)
      SCRIPT="${2:-}"
      shift 2
      ;;
    --language)
      LANG="${2:-}"
      shift 2
      ;;
    --style)
      STYLE="${2:-}"
      shift 2
      ;;
    --errors-to)
      ERRORS_TO="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
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

if [[ -z "$SCRIPT" ]]; then
  echo "--script is required" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$SCRIPT" ]]; then
  echo "Script not found: $SCRIPT" >&2
  exit 1
fi

flags=""
case "$STYLE" in
  h|s)
    flags+="$STYLE"
    ;;
  *)
    echo "Invalid --style: $STYLE (expected h or s)" >&2
    exit 2
    ;;
 esac

case "$ERRORS_TO" in
  stderr)
    flags+="e"
    ;;
  stdout)
    flags+="o"
    ;;
  *)
    echo "Invalid --errors-to: $ERRORS_TO (expected stderr or stdout)" >&2
    exit 2
    ;;
 esac

/usr/bin/osascript -l "$LANG" -s "$flags" "$SCRIPT" "$@"
