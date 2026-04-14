#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/compile.sh" >/dev/null

EXPECTED_DIR="$ROOT_DIR/tests/unit/expected"

fail=0

for expected_path in "$EXPECTED_DIR"/*.txt; do
  [[ -e "$expected_path" ]] || continue

  base_name="$(basename "$expected_path" .txt)"
  script_path="$ROOT_DIR/build/${base_name}.scpt"

  if [[ ! -f "$script_path" ]]; then
    echo "Missing compiled test script: $script_path" >&2
    fail=1
    continue
  fi

  expected="$(cat "$expected_path")"

  set +e
  actual="$(/usr/bin/osascript -s s "$script_path" 2>&1)"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    echo "FAIL (runtime error): $base_name" >&2
    printf '%s\n' "$actual" >&2
    fail=1
    continue
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL (mismatch): $base_name" >&2
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    fail=1
  else
    echo "PASS: $base_name"
  fi

done

exit "$fail"
