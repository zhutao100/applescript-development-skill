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
    [--no-graphics] \
    [--net-host] \
    [--net-softnet] \
    [--net-softnet-allow <cidrs>] \
    [--net-softnet-block <cidrs>] \
    [--net-softnet-expose <ports>] \
    [--net-bridged <iface>] \
    [--no-clipboard] \
    [--no-audio] \
    [--ip-resolver <dhcp|arp|agent>] \
    [--exec-timeout <seconds>] \
    [--force-ssh]

Examples:
  # Run repo integration tests inside a fresh VM clone and write artifacts to ./artifacts/vm
  run_in_vm_tart.sh --base tahoe-base --cmd './scripts/test_integration.sh' --artifacts ./artifacts/vm

  # Clone directly from a remote image reference
  run_in_vm_tart.sh --base ghcr.io/cirruslabs/macos-tahoe-base:latest --cmd 'uname -a'

Notes:
- Requires: Tart installed on the host ("brew install cirruslabs/cli/tart").
- Prefers `tart exec` (guest agent; requires host macOS 14+). Falls back to SSH if `sshpass` is installed.
- If you need `sshpass`, Homebrew provides it as `brew install sshpass`.
- Workspace is mounted read-only by default; artifacts mount is writable.
- If --base is omitted, the script prefers an existing local VM, else uses a default remote image.
- Networking defaults to Tart's shared (NAT) mode. Use `--net-host` or `--net-softnet*` flags to tighten isolation.
- Some networking modes may require root privileges (passwordless sudo) and will fail in non-interactive runs if unavailable.
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
NO_CLIPBOARD=0
NO_AUDIO=0
NET_HOST=0
NET_SOFTNET=0
NET_SOFTNET_ALLOW=""
NET_SOFTNET_BLOCK=""
NET_SOFTNET_EXPOSE=""
NET_BRIDGED=()
IP_RESOLVER=""
EXEC_TIMEOUT=180
FORCE_SSH=0
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
    --no-clipboard)
      NO_CLIPBOARD=1
      shift
      ;;
    --no-audio)
      NO_AUDIO=1
      shift
      ;;
    --net-host)
      NET_HOST=1
      shift
      ;;
    --net-softnet)
      NET_SOFTNET=1
      shift
      ;;
    --net-softnet-allow)
      if [[ $# -lt 2 ]]; then
        echo "error: --net-softnet-allow requires a value" >&2
        usage >&2
        exit 2
      fi
      NET_SOFTNET_ALLOW="$2"
      NET_SOFTNET=1
      shift 2
      ;;
    --net-softnet-block)
      if [[ $# -lt 2 ]]; then
        echo "error: --net-softnet-block requires a value" >&2
        usage >&2
        exit 2
      fi
      NET_SOFTNET_BLOCK="$2"
      NET_SOFTNET=1
      shift 2
      ;;
    --net-softnet-expose)
      if [[ $# -lt 2 ]]; then
        echo "error: --net-softnet-expose requires a value" >&2
        usage >&2
        exit 2
      fi
      NET_SOFTNET_EXPOSE="$2"
      NET_SOFTNET=1
      shift 2
      ;;
    --net-bridged)
      if [[ $# -lt 2 ]]; then
        echo "error: --net-bridged requires a value" >&2
        usage >&2
        exit 2
      fi
      NET_BRIDGED+=("$2")
      shift 2
      ;;
    --ip-resolver)
      if [[ $# -lt 2 ]]; then
        echo "error: --ip-resolver requires a value" >&2
        usage >&2
        exit 2
      fi
      IP_RESOLVER="$2"
      shift 2
      ;;
    --exec-timeout)
      if [[ $# -lt 2 ]]; then
        echo "error: --exec-timeout requires a value" >&2
        usage >&2
        exit 2
      fi
      EXEC_TIMEOUT="$2"
      shift 2
      ;;
    --force-ssh)
      FORCE_SSH=1
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

if [[ -z "$IP_RESOLVER" && "${#NET_BRIDGED[@]}" -gt 0 ]]; then
  # DHCP lease parsing doesn't work for bridged networking.
  IP_RESOLVER="arp"
fi

require_cmd tart

host_macos_major() {
  if ! command -v sw_vers >/dev/null 2>&1; then
    echo 0
    return 0
  fi
  sw_vers -productVersion | awk -F. '{print $1}'
}

tart_has_exec_subcommand() {
  tart help 2>/dev/null | grep -qE '^[[:space:]]*exec[[:space:]]'
}

host_supports_tart_exec() {
  local major
  major="$(host_macos_major)"
  [[ "$major" =~ ^[0-9]+$ ]] || major=0
  if [[ "$major" -lt 14 ]]; then
    return 1
  fi
  tart_has_exec_subcommand
}

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
host_macos_version=$(command -v sw_vers >/dev/null 2>&1 && sw_vers -productVersion || echo unknown)
tart_version=$(tart --version 2>/dev/null || echo unknown)
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
if [[ "$NO_AUDIO" -eq 1 ]]; then
  run_args+=(--no-audio)
fi
if [[ "$NO_CLIPBOARD" -eq 1 ]]; then
  run_args+=(--no-clipboard)
fi
if [[ "$NET_HOST" -eq 1 ]]; then
  run_args+=(--net-host)
fi
if [[ "$NET_SOFTNET" -eq 1 ]]; then
  run_args+=(--net-softnet)
fi
if [[ -n "$NET_SOFTNET_ALLOW" ]]; then
  run_args+=("--net-softnet-allow=${NET_SOFTNET_ALLOW}")
fi
if [[ -n "$NET_SOFTNET_BLOCK" ]]; then
  run_args+=("--net-softnet-block=${NET_SOFTNET_BLOCK}")
fi
if [[ -n "$NET_SOFTNET_EXPOSE" ]]; then
  run_args+=("--net-softnet-expose=${NET_SOFTNET_EXPOSE}")
fi
if [[ "${#NET_BRIDGED[@]}" -gt 0 ]]; then
  for iface in "${NET_BRIDGED[@]}"; do
    run_args+=("--net-bridged=${iface}")
  done
fi
run_args+=(--dir="${workspace_mount}:${WORKSPACE}:ro")
run_args+=(--dir="${artifacts_mount}:${ARTIFACTS}")
run_args+=("$run_vm")

tart "${run_args[@]}" >"$ARTIFACTS/tart_run.log" 2>&1 &
run_pid="$!"

abort_if_run_exited() {
  if [[ -n "$run_pid" ]] && kill -0 "$run_pid" >/dev/null 2>&1; then
    return 0
  fi

  echo "[tart] 'tart run' exited unexpectedly. See: $ARTIFACTS/tart_run.log" >&2
  if [[ -f "$ARTIFACTS/tart_run.log" ]]; then
    tail -n 120 "$ARTIFACTS/tart_run.log" >&2 || true
  fi

  if [[ -f "$ARTIFACTS/tart_run.log" ]] && grep -q "root privileges are required to run" "$ARTIFACTS/tart_run.log"; then
    cat >&2 <<'EOF'
[tart] hint: Some networking modes (e.g. `--net-host`, `--net-softnet*`, `--net-bridged`) may require root privileges.
             Configure passwordless sudo for Tart/Softnet, or omit those flags.
EOF
  fi

  exit 1
}

wait_for_exec_ready() {
  local deadline
  deadline=$((SECONDS + EXEC_TIMEOUT))
  while [[ $SECONDS -lt $deadline ]]; do
    abort_if_run_exited
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
    abort_if_run_exited
    local ip
    if [[ -n "$IP_RESOLVER" ]]; then
      ip="$(tart ip --resolver "$IP_RESOLVER" "$run_vm" 2>/dev/null || true)"
    else
      ip="$(tart ip "$run_vm" 2>/dev/null || true)"
    fi
    if [[ -n "$ip" ]]; then
      VM_IP="$ip"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

wait_for_ssh_ready() {
  local ip="$1"
  local deadline
  deadline=$((SECONDS + 180))

  local ssh_opts=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
    -o KbdInteractiveAuthentication=no
    -o PasswordAuthentication=yes
    -o NumberOfPasswordPrompts=1
    -o ConnectTimeout=5
    -o ConnectionAttempts=1
  )

  while [[ $SECONDS -lt $deadline ]]; do
    abort_if_run_exited
    if sshpass -p admin ssh "${ssh_opts[@]}" admin@"$ip" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

exec_status=0

use_exec=0
if [[ "$FORCE_SSH" -eq 0 ]] && host_supports_tart_exec; then
  use_exec=1
fi

if [[ "$use_exec" -eq 1 ]]; then
  echo "[tart] waiting for guest agent (tart exec)..." >&2
  if wait_for_exec_ready; then
    echo "[tart] exec: $CMD" >&2
    set +e
    tart exec "$run_vm" zsh -lc "cd \"$workspace_in_vm\" && export ASDEV_ARTIFACTS=\"$artifacts_in_vm\" && $CMD" \
      >"$ARTIFACTS/host_stdout.log" 2>"$ARTIFACTS/host_stderr.log"
    exec_status=$?
    set -e
  else
    echo "[tart] tart exec not ready after ${EXEC_TIMEOUT}s" >&2
    use_exec=0
  fi
fi

if [[ "$use_exec" -eq 0 ]]; then
  require_cmd ssh
  if ! command -v sshpass >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: SSH fallback requires 'sshpass' (e.g. 'brew install sshpass').

Options:
- Install sshpass for password-based SSH to Cirrus images (admin/admin).
- Or ensure 'tart exec' works:
  * host macOS 14+ (Sonoma) or newer
  * a non-vanilla image (e.g. '*-base' / '*-xcode') or tart-guest-agent installed+running in the guest
EOF
    exit 2
  fi

  echo "[tart] waiting for ip..." >&2
  VM_IP=""
  if ! wait_for_ip; then
    echo "error: tart ip not ready after timeout" >&2
    exit 1
  fi
  ip="$VM_IP"

  {
    echo "ip=${ip}"
    echo "ip_resolver=${IP_RESOLVER:-default}"
  } >>"$ARTIFACTS/run_meta.txt" 2>/dev/null || true

  echo "[tart] waiting for ssh..." >&2
  if ! wait_for_ssh_ready "$ip"; then
    echo "error: ssh not ready after timeout (Remote Login enabled in guest?)" >&2
    exit 1
  fi

  ssh_opts=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
    -o KbdInteractiveAuthentication=no
    -o PasswordAuthentication=yes
    -o NumberOfPasswordPrompts=1
    -o ConnectTimeout=5
    -o ConnectionAttempts=1
  )

  echo "[tart] ssh: admin@$ip" >&2
  set +e
  sshpass -p admin ssh \
    "${ssh_opts[@]}" \
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
