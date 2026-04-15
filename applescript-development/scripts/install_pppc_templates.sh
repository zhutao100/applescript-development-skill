#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Install PPPC (Privacy Preferences Policy Control) profile templates into a project.

These templates are useful when you manage test machines via MDM and want to pre-approve
Automation (Apple Events) permissions for a stable runner identity.

Usage:
  install_pppc_templates.sh --dest <dir>

Example:
  applescript-development/scripts/install_pppc_templates.sh --dest .

This installs:
  ./mdm/pppc/AppleEvents_PPPC_template.mobileconfig

Notes:
- PPPC profiles generally must be delivered via user-approved MDM to take effect.
- Treat PPPC as a determinism aid; VM isolation remains the primary safety boundary.
USAGE
}

DEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      DEST="${2:-}"
      shift 2
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

if [[ -z "$DEST" ]]; then
  echo "--dest is required" >&2
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/../assets/pppc"

if [[ ! -d "$ASSETS_DIR" ]]; then
  echo "error: assets directory missing: $ASSETS_DIR" >&2
  exit 1
fi

DEST="$(mkdir -p "$DEST" && cd "$DEST" && pwd)"
OUT_DIR="$DEST/mdm/pppc"
mkdir -p "$OUT_DIR"

cp -R "$ASSETS_DIR/"* "$OUT_DIR/"

echo "Installed PPPC templates to: $OUT_DIR" >&2
