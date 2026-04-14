#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Install the AppleScript project template into a destination directory.

Usage:
  install_template.sh --dest <path> [--force]

Options:
  --dest   Destination directory (created if missing).
  --force  Overwrite existing files/directories if they conflict.
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
TEMPLATE_DIR="$ASSETS_DIR/template_project"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "Template not found: $TEMPLATE_DIR" >&2
  exit 1
fi

mkdir -p "$DEST"

# Refuse to clobber common top-level template paths unless --force.
if [[ $FORCE -ne 1 ]]; then
  conflicts=()
  for p in src tests scripts .github Makefile .gitignore README.md; do
    if [[ -e "$DEST/$p" ]]; then
      conflicts+=("$p")
    fi
  done

  if [[ ${#conflicts[@]} -gt 0 ]]; then
    printf 'Refusing to overwrite existing paths in %s:\n' "$DEST" >&2
    printf '  - %s\n' "${conflicts[@]}" >&2
    echo "Re-run with --force to overwrite." >&2
    exit 1
  fi
fi

cp -R "$TEMPLATE_DIR/." "$DEST/"

echo "Installed template into: $DEST"
