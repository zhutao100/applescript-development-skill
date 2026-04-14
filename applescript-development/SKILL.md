---
name: applescript-development
description: Reliable development, testing, and CI workflows for AppleScript automation projects (.applescript) on modern macOS (15+, including macOS 26). Use to scaffold a repo, add a compile gate, run unit-ish golden tests via osascript, segment integration/UI tests that require TCC Automation/Accessibility, and snapshot target app scripting dictionaries.
license: MIT
compatibility: macOS 15+ with /usr/bin/osascript, /usr/bin/osacompile, /usr/bin/sdef. Hosted CI generally supports compile/unit tests only; integration/UI automation requires a logged-in GUI session and pre-provisioned TCC permissions on self-hosted runners.
metadata:
  version: "1.0.0"
  author: "community"
---

# AppleScript Development (macOS 15 / macOS 26+)

## Activation checklist (use this skill when)

- The repo contains **`.applescript`** sources or uses **AppleScript automation** (Apple Events / System Events / UI scripting).
- The task requires **repeatable** build/test, **CI gating**, or **flake reduction**.
- The user mentions **Automation permissions**, **TCC prompts**, **System Events**, **Accessibility**, or **CI runners**.

If the user only needs a one-off AppleScript snippet, you can skip most of this skill and focus on correctness.

## Quick actions (agent-friendly)

### 1) Scaffold a reliable AppleScript project layout

```sh
applescript-development/scripts/install_template.sh --dest .
```

This installs a minimal, CI-friendly scaffold (sources, build scripts, unit-ish tests, optional GitHub Actions workflow).

### 2) Add a GitHub Actions workflow to an existing repo

```sh
applescript-development/scripts/install_github_actions_ci.sh --dest .
```

Creates `.github/workflows/applescript-ci.yml` that runs **compile + unit-ish tests** (safe for hosted runners).

### 3) Compile all `.applescript` sources (compile gate)

```sh
applescript-development/scripts/compile_all.sh --src ./src --out ./build
```

### 4) Run a script deterministically

```sh
applescript-development/scripts/run_osascript.sh --script ./build/cli.scpt --style s -- arg1 arg2
```

- `--style s` uses **recompilable source form** output (`osascript -s s`) for unambiguous assertions.

### 5) Run unit-ish tests (golden output)

If you installed the template, from the project root:

```sh
./scripts/test_unit.sh
```

## Recommended workflow for agents (step-by-step)

### Step 0 — Triage the automation surface

1. List target apps and decide the least brittle surface:
   - **Apple Events (dictionary-driven)**: preferred when the target app is scriptable.
   - **UI scripting (System Events / Accessibility)**: last resort.
2. If the task likely needs UI scripting or integration tests, plan for TCC prompts and CI segmentation.

### Step 1 — Establish a clean build/test contract

1. Ensure `.applescript` is the **source-of-truth** in version control.
2. Add a **compile gate** (`osacompile`) as a first-line quality check.
3. Standardize execution through `osascript` with deterministic output mode (`-s s`).

If starting from scratch, run the template installer (Quick action #1) and work from the scaffold.

### Step 2 — Write “unit-ish” tests first

1. Refactor logic into **pure handlers** (string/list/record transforms).
2. Keep Apple Events / UI calls behind thin wrappers.
3. Test the pure logic using golden outputs (works on hosted CI).

### Step 3 — Add integration/UI tests only where necessary

1. Gate integration tests behind an environment switch (example in template):
   - Run on **self-hosted** runners or dedicated machines where permissions are provisioned.
2. Add explicit timeouts and state polling (avoid blind `delay`).

### Step 4 — Make failures diagnosable

1. Emit structured error reports (phase markers, target app, error number).
2. Save stdout/stderr logs as CI artifacts.

### Step 5 — Snapshot app dictionaries when you depend on them

If your automation depends on a target app’s scripting interface, snapshot its dictionary:

```sh
applescript-development/scripts/snapshot_sdef.sh --app "/Applications/Safari.app" --out ./dictionaries/Safari.sdef
```

Diff snapshots across upgrades to catch contract drift early.

## Deeper details

For TCC/Automation behavior, CI realities, UI scripting reliability patterns, and packaging/signing notes, see:

- [references/REFERENCE.md](references/REFERENCE.md)
