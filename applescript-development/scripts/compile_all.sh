#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Compile all .applescript files under a source directory into .scpt outputs.

Usage:
  compile_all.sh --src <dir> --out <dir> [--language AppleScript]

Notes:
- This is a CI-friendly "compile gate". It catches syntax/compile errors early.
- Outputs mirror the input directory structure.

Example:
  compile_all.sh --src ./src --out ./build
USAGE
}

SRC=""
OUT=""
LANG="AppleScript"

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
    --language)
      LANG="${2:-}"
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

if [[ -z "$SRC" || -z "$OUT" ]]; then
  echo "--src and --out are required" >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$SRC" ]]; then
  echo "Source directory not found: $SRC" >&2
  exit 1
fi

mkdir -p "$OUT"

# Find all .applescript files and compile each to a mirrored .scpt path.
while IFS= read -r -d '' file; do
  rel="${file#$SRC/}"
  out_rel="${rel%.applescript}.scpt"
  out_path="$OUT/$out_rel"

  mkdir -p "$(dirname "$out_path")"
  /usr/bin/osacompile -l "$LANG" -o "$out_path" "$file"
  echo "Compiled: $file -> $out_path"
done < <(find "$SRC" -type f -name '*.applescript' -print0)
