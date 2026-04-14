#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Install a GitHub Actions workflow for AppleScript compile + unit tests.

Usage:
  install_github_actions_ci.sh --dest <path> [--force]

This creates:
  <dest>/.github/workflows/applescript-ci.yml

Options:
  --dest   Destination repository root.
  --force  Overwrite the workflow file if it already exists.
USAGE
}

DEST=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      DEST="${2:-}"
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

if [[ -z "$DEST" ]]; then
  echo "--dest is required" >&2
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$(cd "$SCRIPT_DIR/../assets" && pwd)"
SRC_FILE="$ASSETS_DIR/github_actions/applescript-ci.yml"

if [[ ! -f "$SRC_FILE" ]]; then
  echo "Workflow asset not found: $SRC_FILE" >&2
  exit 1
fi

WORKFLOW_DIR="$DEST/.github/workflows"
DEST_FILE="$WORKFLOW_DIR/applescript-ci.yml"

mkdir -p "$WORKFLOW_DIR"

if [[ -e "$DEST_FILE" && $FORCE -ne 1 ]]; then
  echo "Refusing to overwrite existing workflow: $DEST_FILE" >&2
  echo "Re-run with --force to overwrite." >&2
  exit 1
fi

cp "$SRC_FILE" "$DEST_FILE"

echo "Installed workflow: $DEST_FILE"
