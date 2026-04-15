# Safe testing for agent-authored AppleScript (macOS 15 / macOS 26+)

This reference focuses on **safe, verifiable closed loops** for AppleScript automation developed iteratively by LLM agents.

AppleScript sits on top of **Apple Events** interprocess control. In practice, agent-authored scripts can easily grow from
"app scripting" into UI scripting (System Events / Accessibility), shell execution, and broad side effects.
Treat agent-authored AppleScript as **untrusted code**.

## Recommended approach (2026): disposable macOS VMs per run

The highest-confidence integration loop on modern macOS is:

1. Maintain a **golden macOS VM image** dedicated to automation testing.
2. **Clone the VM per run**, execute tests, collect artifacts.
3. **Delete the clone** (or revert) after each run.

Rationale: process sandboxing on the *runner* cannot reliably prevent the *target app* (Mail, Safari, etc.) from mutating
its own stores once it receives Apple Events.

## Tiered testing architecture

Use a tiered architecture to shift failures left and keep the expensive/slow loop focused.

### Tier 0 — static gates (fast, safe)

- Compile-check (`osacompile`) and enforce timeouts.
- Policy scan before execution:
  - reject `do shell script` (or allowlist it)
  - reject UI scripting via `System Events` unless explicitly required
  - optionally restrict `tell application "..."` targets to an allowlist

This skill provides a conservative scanner:

```sh
applescript-development/scripts/policy_scan.sh --src ./src
```

### Tier 1 — contract tests with mock `.sdef` apps (optional)

When automation depends heavily on a target app dictionary, a useful shift-left technique is building a **mock scriptable app**
that exposes the same `.sdef` dictionary and logs received Apple Events.

You can then validate that agent scripts:

- use the correct object model
- send expected commands in the expected order
- access stable fields/properties

This catches many correctness issues without touching real user data, but it does **not** replace integration tests.

### Tier 2 — integration/UI tests in disposable macOS VMs (primary boundary)

Use VM clones as the primary safety boundary for tests that interact with real apps.

The minimum lifecycle you want is:

```text
clone golden VM -> run VM -> exec test command -> collect artifacts -> stop/delete VM
```

This skill provides a host-side helper for Tart-based runs:

```sh
applescript-development/scripts/run_in_vm_tart.sh \
  --cmd  './scripts/test_integration.sh' \
  --base <golden-vm-or-image-ref> \
  --artifacts ./artifacts/vm \
  --no-graphics
```

Tip: If `--base` is omitted, the helper prefers an existing local VM (for example `macos-26-xcode` or `tahoe-base`) and
otherwise falls back to downloading the default remote image.
Override with `ASDEV_TART_BASE` and/or `ASDEV_TART_DEFAULT_IMAGE`.

The helper:

- mounts the workspace read-only into the VM
- mounts an artifacts directory read-write
- sets `ASDEV_ARTIFACTS` inside the VM so tests have a stable output location

If you installed the template project, it includes a ready-to-run end-to-end example:

```sh
./scripts/test_integration_vm_tart.sh --base <golden-vm-or-image-ref>
# or:
./scripts/test_integration_vm_tart.sh
```

## Tart: concrete setup and primitives

Tart is the default recommendation for **clone-per-run** workflows because it is CLI-first and supports read-only directory
shares plus `tart exec` (guest-agent based) command execution.

### Install Tart

```sh
brew install cirruslabs/cli/tart
```

### Choose a base image

Tart publishes macOS images in an OCI registry. A common starting point for macOS 26 (Tahoe) is:

```sh
tart clone ghcr.io/cirruslabs/macos-tahoe-base:latest tahoe-base
```

Other commonly used images are listed in Tart's Quick Start docs (macOS 26 Tahoe / macOS 15 Sequoia / etc.).

Notes:

- Prefer `*-base` (or `*-xcode`) images for automation runs because they include the Tart guest agent, enabling `tart exec`.
- `*-vanilla` images are closer to stock, but typically require more provisioning.

### Default credentials (Cirrus images)

Cirrus-provided images use:

- Username: `admin`
- Password: `admin`

These credentials work for GUI login and SSH.

### Directory shares (host mounts)

For safe closed loops you want:

- a **read-only** share for inputs (repo/workspace)
- a **read-write** share for outputs (artifacts)

Tart directory shares use VirtioFS. The `--dir` flag supports an optional mount name and options like `ro`.

Example:

```sh
tart run tahoe-base \
  --dir="workspace:$(pwd):ro" \
  --dir="artifacts:$(pwd)/artifacts/vm" \
  --no-graphics
```

On macOS guests, these mounts are auto-mounted under:

```text
/Volumes/My Shared Files/<name>
```

So the example above yields:

- `/Volumes/My Shared Files/workspace` (read-only)
- `/Volumes/My Shared Files/artifacts` (read-write)

### Non-interactive command execution (`tart exec`)

If the guest agent is present and running, you can execute commands without SSH:

```sh
tart exec tahoe-base uname -a
```

If you build your own VM image from scratch, plan to install and enable the Tart guest agent inside the VM before you
expect `tart exec` to work.

### Create a golden VM image from scratch (IPSW)

When you need a VM with custom system settings or a specific restore image, Tart can create a macOS VM from an IPSW:

```sh
tart create --from-ipsw=latest tahoe-vanilla
```

After first boot and installation, Tart's docs recommend at least:

1. Enable auto-login for the test user.
2. Enable Remote Login (SSH).
3. Disable lock screen password re-prompt and screen saver.
4. Optionally configure passwordless sudo for the test user.

Once the VM is in your desired baseline state (including TCC approvals), **stop it and treat it as your golden base**.

## Golden image hardening checklist

Inside the golden VM:

- Use a **dedicated test user**, and avoid signing into personal Apple IDs unless required.
- Seed only synthetic fixtures under a single fixture root.
- Keep the guest's `$HOME` guest-local.
- Mount host "real data" (if any) as **read-only**, and export only explicit artifacts/patches via a dedicated output share.
- Pre-approve required TCC prompts (Automation / Apple Events and, if needed, Accessibility) once, then snapshot/clone.

Also ensure **Remote Application Scripting** is disabled on real machines by default; enable only in lab/VM environments if required.

## TCC provisioning notes (Automation / Accessibility)

### Local dev + VMs (single-machine)

The most pragmatic setup for a local golden VM is still:

1. Run a minimal script that triggers the relevant TCC prompts (Automation / Apple Events and optionally Accessibility).
2. Approve them once inside the golden VM.
3. Stop the VM and clone it per run.

This avoids flaky, prompt-blocked automation runs.

### Managed fleets (MDM / PPPC)

If you control test machines with MDM, PPPC profiles (`com.apple.TCC.configuration-profile-policy`) can pre-approve services.

For Apple Events policies, Apple documents additional fields such as:

- `AEReceiverIdentifier`
- `AEReceiverIdentifierType` (`bundleID` or `path`)
- `AEReceiverCodeRequirement`

This is the supported way to pre-authorize a sender to control a specific receiver.

Important constraints:

- PPPC profiles must be delivered via MDM; do not assume you can locally install them on arbitrary hosts.
- Treat these as *determinism aids*, not as your primary safety boundary.

## Artifact-driven verification

Treat the test loop as "artifact in → artifact out" so pass/fail is objective and diagnosable.

Recommended minimum artifacts per run:

- host-side `stdout` / `stderr`
- a structured result file (JSON) with status and timestamps
- best-effort screenshot(s) for UI scripting failures
- optional fixture integrity manifests (`find + shasum`) before/after the run

The template's `scripts/test_integration.sh` demonstrates the pattern.

## GhostVM (alternative): agent workspaces with snapshots

GhostVM is a strong alternative when you want VM isolation with better interactive ergonomics (GUI inspection, workspace
management) while still supporting:

- VirtioFS shared folders (including read-only)
- snapshots/reverts
- guest-side remote command execution via `vmctl remote` (requires GhostTools in the guest)

Typical workflow shape:

1. Keep a stopped "golden" GhostVM workspace.
2. Start it (optionally headless) with a **read-only** shared folder.
3. Run the harness in-guest via `vmctl remote`.
4. Stop and revert to a clean snapshot.

Example commands:

```sh
# Start headless with a read-only shared folder
vmctl start ~/VMs/dev.GhostVM --headless --shared-folder "$(pwd)" --read-only

# Execute a command inside the guest (requires GhostTools)
vmctl remote --name dev exec uname -a

# Revert snapshot after the run
vmctl stop ~/VMs/dev.GhostVM
vmctl snapshot ~/VMs/dev.GhostVM revert clean-state
```

Limitations versus Tart for this specific closed-loop pattern:

- GhostVM's CLI docs emphasize a single `--shared-folder` entrypoint. If you need *two* concurrent shares (workspace RO + artifacts RW),
  plan for an alternative artifact export path (e.g., in-guest artifact creation + explicit copy-out using GhostTools/file transfer).

## Process sandboxing is optional defense-in-depth

Seatbelt sandboxing can limit what the **runner process** can do, but it cannot prevent side effects inside the target
application.

If you add sandboxing:

- treat it as a supplemental layer only
- keep it opt-in
- avoid `sandbox-exec` as a long-term dependency (it is deprecated)
