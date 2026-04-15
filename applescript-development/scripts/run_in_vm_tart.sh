#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run a command inside a disposable Tart VM cloned from a base image.

This is intended as the primary safety boundary for integration/UI automation:
the VM is cloned per run and deleted afterward.

Usage:
  run_in_vm_tart.sh \
    --cmd  <command-to-run-inside-vm> \
    [--base <vm-or-image-ref>] \
    [--default-image <oci-ref>] \
    [--workspace <host-path>] \
    [--artifacts <host-path>] \
    [--no-graphics]

Examples:
  # Run repo integration tests inside a fresh VM clone and write artifacts to ./artifacts/vm
  run_in_vm_tart.sh --base tahoe-base --cmd './scripts/test_integration.sh' --artifacts ./artifacts/vm

  # Clone directly from a remote image reference
  run_in_vm_tart.sh --base ghcr.io/cirruslabs/macos-tahoe-base:latest --cmd 'uname -a'

Notes:
- Requires: Tart installed on the host ("brew install cirruslabs/cli/tart").
- Prefers `tart exec` (guest agent). Falls back to SSH if `sshpass` is installed.
- If you need `sshpass`, Homebrew provides it as `brew install sshpass`.
- Workspace is mounted read-only by default; artifacts mount is writable.
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
CMD=""
WORKSPACE="$(pwd)"
ARTIFACTS=""
NO_GRAPHICS=0
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
    --cmd)
      if [[ $# -lt 2 ]]; then
        echo "error: --cmd requires a value" >&2
        usage >&2
        exit 2
      fi
      CMD="$2"
      shift 2
      ;;
    --workspace)
      if [[ $# -lt 2 ]]; then
        echo "error: --workspace requires a value" >&2
        usage >&2
        exit 2
      fi
      WORKSPACE="$2"
      shift 2
      ;;
    --artifacts)
      if [[ $# -lt 2 ]]; then
        echo "error: --artifacts requires a value" >&2
        usage >&2
        exit 2
      fi
      ARTIFACTS="$2"
      shift 2
      ;;
    --no-graphics)
      NO_GRAPHICS=1
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

if [[ -z "$CMD" ]]; then
  echo "--cmd is required" >&2
  usage >&2
  exit 2
fi

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

WORKSPACE="$(cd "$WORKSPACE" && pwd)"
if [[ ! -d "$WORKSPACE" ]]; then
  echo "error: workspace directory not found: $WORKSPACE" >&2
  exit 2
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
run_vm="asdev-${timestamp}-$$"

if [[ -z "$ARTIFACTS" ]]; then
  ARTIFACTS="$WORKSPACE/artifacts/vm/${run_vm}"
fi
ARTIFACTS="$(mkdir -p "$ARTIFACTS" && cd "$ARTIFACTS" && pwd)"

cat >"$ARTIFACTS/run_meta.txt" <<EOF
base=${BASE}
run_vm=${run_vm}
workspace_host=${WORKSPACE}
cmd=${CMD}
timestamp=${timestamp}
EOF

workspace_mount="workspace"
artifacts_mount="artifacts"
workspace_in_vm="/Volumes/My Shared Files/${workspace_mount}"
artifacts_in_vm="/Volumes/My Shared Files/${artifacts_mount}"

run_pid=""

cleanup() {
  set +e

  if [[ -n "$run_pid" ]]; then
    # Ask Tart to stop first; `tart run` should exit.
    tart stop "$run_vm" >/dev/null 2>&1 || true
    wait "$run_pid" >/dev/null 2>&1 || true
  fi

  tart delete "$run_vm" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[tart] clone: $BASE -> $run_vm" >&2
tart clone "$BASE" "$run_vm"

echo "[tart] run: $run_vm" >&2
run_args=(run)
if [[ "$NO_GRAPHICS" -eq 1 ]]; then
  run_args+=(--no-graphics)
fi
run_args+=(--dir="${workspace_mount}:${WORKSPACE}:ro")
run_args+=(--dir="${artifacts_mount}:${ARTIFACTS}")
run_args+=("$run_vm")

tart "${run_args[@]}" >"$ARTIFACTS/tart_run.log" 2>&1 &
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

wait_for_ip() {
  local deadline
  deadline=$((SECONDS + 180))
  while [[ $SECONDS -lt $deadline ]]; do
    local ip
    ip="$(tart ip "$run_vm" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

exec_status=0

if has_tart_exec; then
  echo "[tart] waiting for guest agent..." >&2
  if ! wait_for_exec_ready; then
    echo "error: tart exec not ready after timeout" >&2
    exit 1
  fi

  echo "[tart] exec: $CMD" >&2
  set +e
  tart exec "$run_vm" zsh -lc "cd \"$workspace_in_vm\" && export ASDEV_ARTIFACTS=\"$artifacts_in_vm\" && $CMD" \
    >"$ARTIFACTS/host_stdout.log" 2>"$ARTIFACTS/host_stderr.log"
  exec_status=$?
  set -e
else
  require_cmd ssh
  require_cmd sshpass

  echo "[tart] waiting for ip..." >&2
  ip="$(wait_for_ip)" || { echo "error: tart ip not ready after timeout" >&2; exit 1; }

  echo "[tart] ssh: admin@$ip" >&2
  set +e
  sshpass -p admin ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    admin@"$ip" \
    "cd \"$workspace_in_vm\" && export ASDEV_ARTIFACTS=\"$artifacts_in_vm\" && $CMD" \
    >"$ARTIFACTS/host_stdout.log" 2>"$ARTIFACTS/host_stderr.log"
  exec_status=$?
  set -e
fi

if [[ "$exec_status" -ne 0 ]]; then
  echo "[tart] command failed (exit $exec_status). Artifacts: $ARTIFACTS" >&2
  exit "$exec_status"
fi

echo "[tart] command succeeded. Artifacts: $ARTIFACTS" >&2
