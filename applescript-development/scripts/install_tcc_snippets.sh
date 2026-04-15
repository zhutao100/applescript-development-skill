#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Install TCC prompt snippets into a project.

These snippets are intended to be run while provisioning a golden VM image, to trigger:
- Automation (Apple Events) prompts
- Accessibility prompts (for System Events UI scripting)

Usage:
  install_tcc_snippets.sh --dest <dir>

Example:
  applescript-development/scripts/install_tcc_snippets.sh --dest .

Installs:
  ./tcc/snippets/*.applescript

Notes:
- Running these snippets may trigger system prompts.
- Use them inside disposable VMs where you can safely approve once and snapshot/clone.
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
ASSETS_DIR="$SCRIPT_DIR/../assets/tcc_snippets"

if [[ ! -d "$ASSETS_DIR" ]]; then
  echo "error: assets directory missing: $ASSETS_DIR" >&2
  exit 1
fi

DEST="$(mkdir -p "$DEST" && cd "$DEST" && pwd)"
OUT_DIR="$DEST/tcc/snippets"
mkdir -p "$OUT_DIR"

cp -R "$ASSETS_DIR/"* "$OUT_DIR/"

echo "Installed TCC snippets to: $OUT_DIR" >&2
