#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

mkdir -p "$BUILD_DIR"

# Compile the CLI by concatenating sources in order.
/usr/bin/osacompile -o "$BUILD_DIR/cli.scpt" \
  "$ROOT_DIR/src/lib.applescript" \
  "$ROOT_DIR/src/cli.applescript"

# Compile unit tests (each test script is compiled together with lib.applescript).
/usr/bin/osacompile -o "$BUILD_DIR/test_cli.scpt" \
  "$ROOT_DIR/src/lib.applescript" \
  "$ROOT_DIR/tests/unit/test_cli.applescript"

echo "Compiled scripts to: $BUILD_DIR"
