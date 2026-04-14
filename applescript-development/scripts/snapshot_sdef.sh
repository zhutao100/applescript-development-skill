#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Snapshot an app's scripting dictionary (sdef) to a file for diffing and contract tests.

Usage:
  snapshot_sdef.sh --app <.app path> --out <file> [--force]

Examples:
  snapshot_sdef.sh --app "/Applications/Safari.app" --out ./dictionaries/Safari.sdef
  snapshot_sdef.sh --app "/System/Library/CoreServices/Finder.app" --out ./dictionaries/Finder.sdef
USAGE
}

APP=""
OUT=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP="${2:-}"
      shift 2
      ;;
    --out)
      OUT="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=1
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

if [[ -z "$APP" || -z "$OUT" ]]; then
  echo "--app and --out are required" >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  exit 1
fi

if [[ -e "$OUT" && $FORCE -ne 1 ]]; then
  echo "Refusing to overwrite existing file: $OUT" >&2
  echo "Re-run with --force to overwrite." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

/usr/bin/sdef "$APP" > "$OUT"

echo "Wrote sdef snapshot: $OUT"
