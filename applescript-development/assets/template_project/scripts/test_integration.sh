#!/usr/bin/env bash
set -euo pipefail

# Integration test entrypoint intended to run inside a disposable macOS VM.
#
# This script avoids writing to the mounted workspace (which is typically mounted read-only)
# by compiling into a temporary directory.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ARTIFACTS_DIR="${ASDEV_ARTIFACTS:-$ROOT_DIR/artifacts/integration}"
mkdir -p "$ARTIFACTS_DIR"

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"$ARTIFACTS_DIR/run_meta.txt" <<EOF
timestamp_utc=${timestamp}
root_dir=${ROOT_DIR}
uname=$(uname -a)
EOF

# Optional fixture integrity check.
#
# If FIXTURE_ROOT points at a directory inside the VM (e.g., seeded synthetic Mail data),
# we compute a manifest before/after and diff it.
fixture_manifest() {
  local root="$1"
  local out="$2"
  (cd "$root" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) >"$out"
}

if [[ -n "${FIXTURE_ROOT:-}" && -d "${FIXTURE_ROOT}" ]]; then
  fixture_manifest "${FIXTURE_ROOT}" "$ARTIFACTS_DIR/fixture_manifest_before.txt" || true
fi

tmp_build="$(mktemp -d)"
trap 'rm -rf "$tmp_build"' EXIT

compile() {
  /usr/bin/osacompile -o "$tmp_build/cli.scpt" \
    "$ROOT_DIR/src/lib.applescript" \
    "$ROOT_DIR/src/cli.applescript"

  /usr/bin/osacompile -o "$tmp_build/test_cli.scpt" \
    "$ROOT_DIR/src/lib.applescript" \
    "$ROOT_DIR/tests/unit/test_cli.applescript"
}

compile >"$ARTIFACTS_DIR/compile_stdout.log" 2>"$ARTIFACTS_DIR/compile_stderr.log"

expected_path="$ROOT_DIR/tests/unit/expected/test_cli.txt"
expected="$(cat "$expected_path")"

set +e
actual="$(/usr/bin/osascript -s s "$tmp_build/test_cli.scpt" 2>&1)"
status=$?
set -e

printf '%s\n' "$actual" >"$ARTIFACTS_DIR/test_stdout.txt"

result="pass"
if [[ $status -ne 0 ]]; then
  result="runtime_error"
elif [[ "$actual" != "$expected" ]]; then
  result="mismatch"
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >"$ARTIFACTS_DIR/diff.txt" || true
fi

if [[ -n "${FIXTURE_ROOT:-}" && -d "${FIXTURE_ROOT}" ]]; then
  fixture_manifest "${FIXTURE_ROOT}" "$ARTIFACTS_DIR/fixture_manifest_after.txt" || true
  diff -u "$ARTIFACTS_DIR/fixture_manifest_before.txt" "$ARTIFACTS_DIR/fixture_manifest_after.txt" \
    >"$ARTIFACTS_DIR/fixture_diff.txt" || true
fi

# Best-effort screenshot capture (useful for UI scripting failures).
if command -v screencapture >/dev/null 2>&1; then
  screencapture -x "$ARTIFACTS_DIR/screenshot.png" >/dev/null 2>&1 || true
fi

cat >"$ARTIFACTS_DIR/result.json" <<EOF
{
  "timestamp_utc": "${timestamp}",
  "result": "${result}",
  "osascript_status": ${status}
}
EOF

case "$result" in
  pass)
    echo "PASS" >&2
    exit 0
    ;;
  *)
    echo "FAIL: ${result} (artifacts: ${ARTIFACTS_DIR})" >&2
    exit 1
    ;;
esac
