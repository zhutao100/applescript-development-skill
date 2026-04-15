#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run integration tests inside a disposable Tart VM cloned per run.

Usage:
  test_integration_vm_tart.sh [--base <vm-or-image-ref>] [--default-image <oci-ref>] [--artifacts <dir>] [--no-graphics] [--policy-strict]

Examples:
  ./scripts/test_integration_vm_tart.sh --base tahoe-base --artifacts ./artifacts/vm
  ./scripts/test_integration_vm_tart.sh --base ghcr.io/cirruslabs/macos-tahoe-base:latest
  ./scripts/test_integration_vm_tart.sh   # auto: prefer local VM, else default image

Notes:
- Workspace is mounted read-only.
- The guest entrypoint is ./scripts/test_integration.sh.
- If --base is omitted, the script prefers an existing local VM, else uses a default remote image.
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: missing required command: $cmd" >&2
    exit 2
  fi
}

BASE=""
ARTIFACTS_ROOT=""
NO_GRAPHICS=0
POLICY_STRICT=0
DEFAULT_IMAGE="${ASDEV_TART_DEFAULT_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      if [[ $# -lt 2 ]]; then
        echo "error: --base requires a value" >&2
        usage >&2
        exit 2
      fi
      BASE="$2"
      shift 2
      ;;
    --default-image)
      if [[ $# -lt 2 ]]; then
        echo "error: --default-image requires a value" >&2
        usage >&2
        exit 2
      fi
      DEFAULT_IMAGE="$2"
      shift 2
      ;;
    --artifacts)
      if [[ $# -lt 2 ]]; then
        echo "error: --artifacts requires a value" >&2
        usage >&2
        exit 2
      fi
      ARTIFACTS_ROOT="$2"
      shift 2
      ;;
    --no-graphics)
      NO_GRAPHICS=1
      shift
      ;;
    --policy-strict)
      POLICY_STRICT=1
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

require_cmd tart

looks_like_oci_ref() {
  local ref="$1"
  [[ "$ref" == *"/"* ]]
}

tart_vm_exists() {
  local name="$1"
  local names=""
  if names="$(tart list --source local --quiet 2>/dev/null)"; then
    grep -Fqx "$name" <<<"$names"
    return $?
  fi
  # Fallback for older Tart versions.
  names="$(tart list 2>/dev/null | awk 'NR==1{next} {print $1}')"
  grep -Fqx "$name" <<<"$names"
}

resolve_base() {
  local requested="${1:-}"

  if [[ -z "$requested" && -n "${ASDEV_TART_BASE:-}" ]]; then
    requested="${ASDEV_TART_BASE}"
  fi

  if [[ -n "$requested" ]]; then
    if tart_vm_exists "$requested"; then
      echo "$requested"
      return 0
    fi
    if looks_like_oci_ref "$requested"; then
      echo "$requested"
      return 0
    fi

    echo "[tart] base not found locally: ${requested}" >&2
    echo "[tart] falling back to default image: ${DEFAULT_IMAGE}" >&2
    echo "${DEFAULT_IMAGE}"
    return 0
  fi

  local candidates=()
  if [[ -n "${ASDEV_TART_PREFERRED_BASES:-}" ]]; then
    local normalized
    normalized="${ASDEV_TART_PREFERRED_BASES//,/ }"
    # shellcheck disable=SC2206
    candidates+=(${normalized})
  fi
  candidates+=(
    "macos-26-xcode"
    "asdev-tahoe"
    "tahoe-base"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    [[ -z "$candidate" ]] && continue
    if tart_vm_exists "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  echo "${DEFAULT_IMAGE}"
}

BASE="$(resolve_base "$BASE")"
if tart_vm_exists "$BASE"; then
  echo "[tart] using local base VM: ${BASE}" >&2
else
  echo "[tart] using base image reference: ${BASE}" >&2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S)"
run_vm="asproj-${timestamp}-$$"

if [[ -z "$ARTIFACTS_ROOT" ]]; then
  ARTIFACTS_ROOT="$ROOT_DIR/artifacts/vm"
fi

run_artifacts="$ARTIFACTS_ROOT/$run_vm"
mkdir -p "$run_artifacts"
run_artifacts="$(cd "$run_artifacts" && pwd)"

echo "[tier0] policy scan" >&2
policy_args=(--src "$ROOT_DIR/src")
if [[ "$POLICY_STRICT" -eq 1 ]]; then
  policy_args+=(--strict)
fi
"$ROOT_DIR/scripts/policy_scan.sh" "${policy_args[@]}"

echo "[tart] clone: $BASE -> $run_vm" >&2
tart clone "$BASE" "$run_vm"

workspace_mount="workspace"
artifacts_mount="artifacts"
workspace_in_vm="/Volumes/My Shared Files/${workspace_mount}"
artifacts_in_vm="/Volumes/My Shared Files/${artifacts_mount}"

run_pid=""
# shellcheck disable=SC2329
cleanup() {
  set +e
  if [[ -n "$run_pid" ]]; then
    tart stop "$run_vm" >/dev/null 2>&1 || true
    wait "$run_pid" >/dev/null 2>&1 || true
  fi
  tart delete "$run_vm" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_args=(run)
if [[ "$NO_GRAPHICS" -eq 1 ]]; then
  run_args+=(--no-graphics)
fi
run_args+=(--dir="${workspace_mount}:${ROOT_DIR}:ro")
run_args+=(--dir="${artifacts_mount}:${run_artifacts}")
run_args+=("$run_vm")

echo "[tart] run: $run_vm" >&2
tart "${run_args[@]}" >"$run_artifacts/tart_run.log" 2>&1 &
run_pid="$!"

has_tart_exec() {
  tart help 2>/dev/null | grep -qE '^[[:space:]]*exec[[:space:]]'
}

wait_for_exec_ready() {
  local deadline
  deadline=$((SECONDS + 180))
  while [[ $SECONDS -lt $deadline ]]; do
    if tart exec "$run_vm" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

if ! has_tart_exec; then
  echo "error: this workflow requires 'tart exec' (guest agent)" >&2
  exit 2
fi

echo "[tart] waiting for guest agent..." >&2
wait_for_exec_ready || { echo "error: tart exec not ready after timeout" >&2; exit 1; }

echo "[tier2] integration in disposable VM" >&2
set +e
tart exec "$run_vm" zsh -lc "cd \"$workspace_in_vm\" && export ASDEV_ARTIFACTS=\"$artifacts_in_vm\" && ./scripts/test_integration.sh" \
  >"$run_artifacts/host_stdout.log" 2>"$run_artifacts/host_stderr.log"
status=$?
set -e

echo "Artifacts: $run_artifacts" >&2
exit "$status"
