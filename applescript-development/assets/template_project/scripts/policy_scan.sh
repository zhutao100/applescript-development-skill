#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Static policy scan for AppleScript sources.

Usage:
  policy_scan.sh --src <dir> [--policy <file>] [--strict]
  policy_scan.sh --files <file> [<file> ...] [--policy <file>] [--strict]

Options:
  --src <dir>       Directory to recursively scan for *.applescript
  --files <...>     Explicit list of *.applescript files
  --policy <file>   Bash policy file to source (defaults to policy/applescript-policy.bash)
  --strict          Treat all warnings as errors

Exit codes:
  0  No policy violations (warnings may be present unless --strict)
  1  Policy violations (or warnings treated as errors)
  2  Invalid usage
USAGE
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_POLICY_FILE="$ROOT_DIR/policy/applescript-policy.bash"

SRC_DIR=""
POLICY_FILE="$DEFAULT_POLICY_FILE"
STRICT=0

FILES=()
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)
      MODE="src"
      SRC_DIR="${2:-}"
      shift 2
      ;;
    --files)
      MODE="files"
      shift
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --policy|--strict|-h|--help)
            break
            ;;
          *)
            FILES+=("$1")
            shift
            ;;
        esac
      done
      ;;
    --policy)
      POLICY_FILE="${2:-}"
      shift 2
      ;;
    --strict)
      STRICT=1
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

if [[ -z "$MODE" ]]; then
  echo "Either --src or --files is required" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "Policy file not found: $POLICY_FILE" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$POLICY_FILE"

# Defaults (policy file may omit some settings).
: "${POLICY_FORBID_DO_SHELL_SCRIPT:=0}"
: "${POLICY_FORBID_SYSTEM_EVENTS:=0}"
: "${POLICY_REQUIRE_TELL_ALLOWLIST:=0}"

if ! declare -p POLICY_ALLOW_TELL_APPS >/dev/null 2>&1; then
  POLICY_ALLOW_TELL_APPS=()
fi
if ! declare -p POLICY_DENY_REGEX >/dev/null 2>&1; then
  POLICY_DENY_REGEX=()
fi

deny_patterns=()

if [[ "${POLICY_FORBID_DO_SHELL_SCRIPT}" -eq 1 ]]; then
  deny_patterns+=('(^|[^[:alpha:]])do[[:space:]]+shell[[:space:]]+script([^[:alpha:]]|$)')
fi
if [[ "${POLICY_FORBID_SYSTEM_EVENTS}" -eq 1 ]]; then
  deny_patterns+=('tell[[:space:]]+(application|app)[[:space:]]+"System[[:space:]]+Events"')
fi

deny_patterns+=("${POLICY_DENY_REGEX[@]}")

if [[ "$MODE" == "src" ]]; then
  if [[ -z "$SRC_DIR" ]]; then
    echo "--src requires a directory" >&2
    exit 2
  fi
  if [[ ! -d "$SRC_DIR" ]]; then
    echo "Source directory not found: $SRC_DIR" >&2
    exit 2
  fi

  while IFS= read -r -d '' f; do
    FILES+=("$f")
  done < <(find "$SRC_DIR" -type f -name '*.applescript' -print0)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No .applescript files found." >&2
  exit 0
fi

errors=0
warnings=0

print_match_block() {
  local file="$1"
  local label="$2"
  local regex="$3"

  local matches
  matches="$(LC_ALL=C grep -nE "$regex" "$file" || true)"
  if [[ -n "$matches" ]]; then
    printf '%s: %s\n' "$file" "$label" >&2
    printf '%s\n' "$matches" | sed 's/^/  /' >&2
    return 0
  fi
  return 1
}

tell_targets_in_file() {
  LC_ALL=C grep -nE 'tell[[:space:]]+(application|app)([[:space:]]+id)?[[:space:]]+"[^"]+"' "$1" \
    | sed -nE 's/.*tell[[:space:]]+(application|app)([[:space:]]+id)?[[:space:]]+"([^"]+)".*/\3/p' \
    | awk '!seen[$0]++'
}

is_allowed_target() {
  local target="$1"
  for allowed in "${POLICY_ALLOW_TELL_APPS[@]}"; do
    if [[ "$target" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Skipping missing file: $f" >&2
    continue
  fi

  for deny in "${deny_patterns[@]}"; do
    if print_match_block "$f" "DENY: matched pattern: $deny" "$deny"; then
      errors=$((errors + 1))
    fi
  done

  while IFS= read -r target; do
    [[ -z "$target" ]] && continue

    if [[ ${#POLICY_ALLOW_TELL_APPS[@]} -gt 0 && "${POLICY_REQUIRE_TELL_ALLOWLIST}" -eq 1 ]]; then
      if ! is_allowed_target "$target"; then
        echo "$f: DENY: tell target not in allowlist: $target" >&2
        errors=$((errors + 1))
      fi
    else
      echo "$f: WARN: tell target detected: $target" >&2
      warnings=$((warnings + 1))
    fi
  done < <(tell_targets_in_file "$f" || true)
done

if [[ "$STRICT" -eq 1 && "$warnings" -gt 0 ]]; then
  errors=$((errors + warnings))
fi

if [[ "$errors" -gt 0 ]]; then
  echo "Policy scan failed: ${errors} issue(s) (${warnings} warning(s))." >&2
  exit 1
fi

if [[ "$warnings" -gt 0 ]]; then
  echo "Policy scan passed with warnings: ${warnings}." >&2
else
  echo "Policy scan passed." >&2
fi
