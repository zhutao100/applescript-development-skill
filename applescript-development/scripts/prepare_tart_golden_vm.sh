#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Prepare a "golden" macOS VM for safe AppleScript integration tests using Tart.

This helper is intentionally lightweight: it only creates/clones the VM and optionally
starts it so you can complete interactive provisioning (TCC approvals, fixtures, etc.).

Usage:
  prepare_tart_golden_vm.sh --name <vm-name> [options]

Options:
  --name <vm-name>         Local Tart VM name to create/clone (required)
  --image <vm|oci-ref>     Source VM name or remote image reference to clone (default: prefer local, else ghcr.io/cirruslabs/macos-tahoe-base:latest)
  --from-ipsw <path|latest>
                           Create from an IPSW instead of cloning a remote image
  --disk-size <gb>         Disk size (GB) when using --from-ipsw (default: Tart default)
  --disk-format <raw|asif> Disk format when using --from-ipsw (asif requires macOS 26+ host; default: Tart default)
  --run                    Start the VM after creation
  --no-graphics            Start without a GUI window (use with --run)
  --force                  Delete any existing local VM with the same --name first

Examples:
  # Recommended: clone a prebuilt macOS 26 "base" image (includes guest agent)
  prepare_tart_golden_vm.sh --name asdev-tahoe --image ghcr.io/cirruslabs/macos-tahoe-base:latest --run

  # Create from latest IPSW (requires interactive macOS install on first boot)
  prepare_tart_golden_vm.sh --name asdev-tahoe-vanilla --from-ipsw latest --run

Notes:
- Requires Tart installed on the host: brew install cirruslabs/cli/tart
- After provisioning, STOP the VM and use it as your base with scripts/run_in_vm_tart.sh.
- If --image is omitted, this script prefers an existing local VM, else uses the default remote image.
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: missing required command: $cmd" >&2
    exit 2
  fi
}

NAME=""
IMAGE="${ASDEV_TART_DEFAULT_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
IMAGE_SPECIFIED=0
FROM_IPSW=""
DISK_SIZE=""
DISK_FORMAT=""
RUN=0
NO_GRAPHICS=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      if [[ $# -lt 2 ]]; then
        echo "error: --name requires a value" >&2
        usage >&2
        exit 2
      fi
      NAME="$2"
      shift 2
      ;;
    --image)
      if [[ $# -lt 2 ]]; then
        echo "error: --image requires a value" >&2
        usage >&2
        exit 2
      fi
      IMAGE="$2"
      IMAGE_SPECIFIED=1
      shift 2
      ;;
    --from-ipsw)
      if [[ $# -lt 2 ]]; then
        echo "error: --from-ipsw requires a value" >&2
        usage >&2
        exit 2
      fi
      FROM_IPSW="$2"
      shift 2
      ;;
    --disk-size)
      if [[ $# -lt 2 ]]; then
        echo "error: --disk-size requires a value" >&2
        usage >&2
        exit 2
      fi
      DISK_SIZE="$2"
      shift 2
      ;;
    --disk-format)
      if [[ $# -lt 2 ]]; then
        echo "error: --disk-format requires a value" >&2
        usage >&2
        exit 2
      fi
      DISK_FORMAT="$2"
      shift 2
      ;;
    --run)
      RUN=1
      shift
      ;;
    --no-graphics)
      NO_GRAPHICS=1
      shift
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

if [[ -z "$NAME" ]]; then
  echo "--name is required" >&2
  usage >&2
  exit 2
fi

require_cmd tart

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

NEED_CREATE=1
if tart_vm_exists "$NAME"; then
  if [[ "$FORCE" -eq 1 ]]; then
    echo "[tart] deleting existing VM: $NAME" >&2
    tart delete "$NAME" >/dev/null
  else
    echo "[tart] VM already exists: $NAME" >&2
    NEED_CREATE=0
    if [[ "$RUN" -eq 1 ]]; then
      echo "[tart] continuing with existing VM (--run requested)" >&2
    else
      echo "Use --run to start it, --force to delete and recreate, or choose a different --name." >&2
      exit 0
    fi
  fi
fi

if [[ "$NEED_CREATE" -eq 1 ]]; then
  if [[ -n "$FROM_IPSW" ]]; then
    echo "[tart] create: --from-ipsw=$FROM_IPSW $NAME" >&2
    create_args=(create "--from-ipsw=$FROM_IPSW")
    if [[ -n "$DISK_SIZE" ]]; then
      create_args+=("--disk-size=$DISK_SIZE")
    fi
    if [[ -n "$DISK_FORMAT" ]]; then
      create_args+=("--disk-format=$DISK_FORMAT")
    fi
    create_args+=("$NAME")
    tart "${create_args[@]}"
  else
    source_image="$IMAGE"
    if [[ "$IMAGE_SPECIFIED" -eq 0 ]]; then
      candidates=()
      if [[ -n "${ASDEV_TART_PREFERRED_BASES:-}" ]]; then
        normalized="${ASDEV_TART_PREFERRED_BASES//,/ }"
        # shellcheck disable=SC2206
        candidates+=(${normalized})
      fi
      candidates+=(
        "macos-26-xcode"
        "tahoe-base"
      )
      for candidate in "${candidates[@]}"; do
        [[ -z "$candidate" ]] && continue
        if tart_vm_exists "$candidate"; then
          source_image="$candidate"
          break
        fi
      done
    fi

    echo "[tart] clone: $source_image -> $NAME" >&2
    tart clone "$source_image" "$NAME"
  fi
fi

cat >&2 <<'NEXT'

Next steps to turn this into a stable "golden" automation image:

1) Log in (or complete install) and configure baseline usability:
   - Enable auto-login for the test user.
   - Enable Remote Login (SSH) if you plan to use SSH fallback.
   - Disable screen saver / lock screen password re-prompt.

2) Bake TCC approvals into the image:
   - Automation (Apple Events) approvals for your runner identity (Terminal, your CI runner, etc.).
   - Accessibility approvals if you use System Events UI scripting.

   Practical method:
   - Run a tiny script that triggers the prompt.
   - Approve once.
   - Repeat for each target app you control.

3) Seed only synthetic fixtures (Mailboxes, documents, etc.) inside the VM.

4) Ensure Tart Guest Agent is installed and configured (enables `tart exec` and clipboard).

   - If you cloned a Cirrus `*-base` / `*-xcode` image, guest agent is already present.
   - If you created from an IPSW (or used a `*-vanilla` image), install it inside the VM:

       brew install cirruslabs/cli/tart-guest-agent

     Then install the launchd plists (templates provided in this skill):

       applescript-development/assets/tart_guest_agent/org.cirruslabs.tart-guest-daemon.plist
       applescript-development/assets/tart_guest_agent/org.cirruslabs.tart-guest-agent.plist

     Copy them into:

       /Library/LaunchDaemons/org.cirruslabs.tart-guest-daemon.plist
       /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist

     and reboot (or stop/start) the VM to ensure they are loaded.

     These templates assume Apple Silicon Homebrew prefix (`/opt/homebrew`) and a test user named `admin`.
     If your VM differs, adjust `ProgramArguments` and `WorkingDirectory` in the plists.

     Note: for AppleScript/TCC work you typically want the agent variant (LaunchAgent),
     so commands executed via `tart exec` run as the logged-in test user, not root.

5) Stop the VM and treat it as a read-only base.

Then use the disposable-per-run harness:
  applescript-development/scripts/run_in_vm_tart.sh --base <this-vm-name> --cmd './scripts/test_integration.sh'

NEXT

if [[ "$RUN" -eq 1 ]]; then
  run_args=(run)
  if [[ "$NO_GRAPHICS" -eq 1 ]]; then
    run_args+=(--no-graphics)
  fi
  run_args+=("$NAME")

  echo "[tart] run: $NAME" >&2
  tart "${run_args[@]}"
fi
