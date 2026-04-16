#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run integration tests inside a disposable Tart VM cloned per run.

Usage:
  test_integration_vm_tart.sh \
    [--base <vm-or-image-ref>] \
    [--default-image <oci-ref>] \
    [--artifacts <dir>] \
    [--no-graphics] \
    [--policy-strict] \
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
  ./scripts/test_integration_vm_tart.sh --base tahoe-base --artifacts ./artifacts/vm
  ./scripts/test_integration_vm_tart.sh --base ghcr.io/cirruslabs/macos-tahoe-base:latest
  ./scripts/test_integration_vm_tart.sh --net-host
  ./scripts/test_integration_vm_tart.sh   # auto: prefer local VM, else default image

Notes:
- Workspace is mounted read-only.
- The guest entrypoint is ./scripts/test_integration.sh.
- Prefers `tart exec` (guest agent; host macOS 14+). Falls back to SSH if `sshpass` is installed.
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
ARTIFACTS_ROOT=""
NO_GRAPHICS=0
POLICY_STRICT=0
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
      [[ $# -ge 2 ]] || { echo "error: --base requires a value" >&2; usage >&2; exit 2; }
      BASE="$2"; shift 2 ;;
    --default-image)
      [[ $# -ge 2 ]] || { echo "error: --default-image requires a value" >&2; usage >&2; exit 2; }
      DEFAULT_IMAGE="$2"; shift 2 ;;
    --artifacts)
      [[ $# -ge 2 ]] || { echo "error: --artifacts requires a value" >&2; usage >&2; exit 2; }
      ARTIFACTS_ROOT="$2"; shift 2 ;;
    --no-graphics)
      NO_GRAPHICS=1; shift ;;
    --policy-strict)
      POLICY_STRICT=1; shift ;;
    --no-clipboard)
      NO_CLIPBOARD=1; shift ;;
    --no-audio)
      NO_AUDIO=1; shift ;;
    --net-host)
      NET_HOST=1; shift ;;
    --net-softnet)
      NET_SOFTNET=1; shift ;;
    --net-softnet-allow)
      [[ $# -ge 2 ]] || { echo "error: --net-softnet-allow requires a value" >&2; usage >&2; exit 2; }
      NET_SOFTNET_ALLOW="$2"; NET_SOFTNET=1; shift 2 ;;
    --net-softnet-block)
      [[ $# -ge 2 ]] || { echo "error: --net-softnet-block requires a value" >&2; usage >&2; exit 2; }
      NET_SOFTNET_BLOCK="$2"; NET_SOFTNET=1; shift 2 ;;
    --net-softnet-expose)
      [[ $# -ge 2 ]] || { echo "error: --net-softnet-expose requires a value" >&2; usage >&2; exit 2; }
      NET_SOFTNET_EXPOSE="$2"; NET_SOFTNET=1; shift 2 ;;
    --net-bridged)
      [[ $# -ge 2 ]] || { echo "error: --net-bridged requires a value" >&2; usage >&2; exit 2; }
      NET_BRIDGED+=("$2"); shift 2 ;;
    --ip-resolver)
      [[ $# -ge 2 ]] || { echo "error: --ip-resolver requires a value" >&2; usage >&2; exit 2; }
      IP_RESOLVER="$2"; shift 2 ;;
    --exec-timeout)
      [[ $# -ge 2 ]] || { echo "error: --exec-timeout requires a value" >&2; usage >&2; exit 2; }
      EXEC_TIMEOUT="$2"; shift 2 ;;
    --force-ssh)
      FORCE_SSH=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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
  [[ "$major" -ge 14 ]] || return 1
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

if [[ -z "$IP_RESOLVER" && "${#NET_BRIDGED[@]}" -gt 0 ]]; then
  IP_RESOLVER="arp"
fi

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
run_args+=(--dir="${workspace_mount}:${ROOT_DIR}:ro")
run_args+=(--dir="${artifacts_mount}:${run_artifacts}")
run_args+=("$run_vm")

echo "[tart] run: $run_vm" >&2
tart "${run_args[@]}" >"$run_artifacts/tart_run.log" 2>&1 &
run_pid="$!"

abort_if_run_exited() {
  if [[ -n "$run_pid" ]] && kill -0 "$run_pid" >/dev/null 2>&1; then
    return 0
  fi

  echo "[tart] 'tart run' exited unexpectedly. See: $run_artifacts/tart_run.log" >&2
  if [[ -f "$run_artifacts/tart_run.log" ]]; then
    tail -n 120 "$run_artifacts/tart_run.log" >&2 || true
  fi

  if [[ -f "$run_artifacts/tart_run.log" ]] && grep -q "root privileges are required to run" "$run_artifacts/tart_run.log"; then
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

status=0

use_exec=0
if [[ "$FORCE_SSH" -eq 0 ]] && host_supports_tart_exec; then
  use_exec=1
fi

if [[ "$use_exec" -eq 1 ]]; then
  echo "[tart] waiting for guest agent (tart exec)..." >&2
  if wait_for_exec_ready; then
    echo "[tier2] integration in disposable VM (tart exec)" >&2
    set +e
    tart exec "$run_vm" zsh -lc "cd \"$workspace_in_vm\" && export ASDEV_ARTIFACTS=\"$artifacts_in_vm\" && ./scripts/test_integration.sh" \
      >"$run_artifacts/host_stdout.log" 2>"$run_artifacts/host_stderr.log"
    status=$?
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

  echo "[tier2] integration in disposable VM (ssh)" >&2
  set +e
  sshpass -p admin ssh \
    "${ssh_opts[@]}" \
    admin@"$ip" \
    "cd \"$workspace_in_vm\" && export ASDEV_ARTIFACTS=\"$artifacts_in_vm\" && ./scripts/test_integration.sh" \
    >"$run_artifacts/host_stdout.log" 2>"$run_artifacts/host_stderr.log"
  status=$?
  set -e
fi

echo "Artifacts: $run_artifacts" >&2
exit "$status"
