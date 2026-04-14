# AppleScript Development Reference (macOS 15 / macOS 26+)

This reference is intentionally more detailed than `SKILL.md` and is meant to be loaded only when needed.

## 1) Core toolchain (built-in)

### Script Editor (interactive debugging)

- **Log History / event tracking**: use *Window → Log History* to see a hierarchical view of events and timings while a script runs. Apple documents this workflow in the Script Editor User Guide.
- **Dictionary viewer**: *Window → Library* then open a target app dictionary to see supported objects/commands and suites.

These features are crucial for deciding whether your automation can be done via Apple Events (preferred) or requires UI scripting.

### CLI tools (repeatable dev + CI)

macOS ships the Open Scripting Architecture (OSA) command-line tools:

- `osascript`: execute AppleScript (or other OSA languages) from files, `-e`, or stdin.
- `osacompile`: compile `.applescript` sources into compiled scripts (`.scpt`) or applets (`.app`).
- `osadecompile`: print the source text of a compiled script.
- `osalang`: list installed OSA languages.
- `sdef`: extract a target app’s scripting definition (dictionary) to XML.
- `sdp`: transform an `sdef` into other formats (mostly relevant for ScriptingBridge or for building scriptable apps).

Practical “preflight” checks:

```sh
command -v osascript osacompile osadecompile osalang sdef
osascript -e 'return "ok"'
osacompile -o /tmp/compile-check.scpt -e 'return 1'
osadecompile /tmp/compile-check.scpt | head
```

### Deterministic output for tests

Use `osascript -s s` to print results in **recompilable source form** (unambiguous for lists/records), instead of the default human-readable formatting:

```sh
osascript -s s ./build/cli.scpt -- arg1 arg2
```

For golden tests where you want to compare *script errors* as part of output, route errors to stdout:

```sh
osascript -s o -e 'error "boom" number 42'
```

## 2) Recommended repository architecture

A reliable AppleScript project is easier to test when it looks like a small software product:

```text
src/                 # plain-text .applescript sources (git-friendly)
build/               # generated .scpt (ignored by git)
scripts/             # build/test helpers
tests/unit/          # unit-ish tests (no AppleEvents / no UI)
tests/integration/   # AppleEvents tests (requires Automation permission)
tests/ui/            # UI scripting tests (requires Accessibility; last resort)
dictionaries/        # optional: sdef snapshots for contract drift detection
```

The template installed by `scripts/install_template.sh` follows this structure.

## 3) Testing strategy that actually works

### A) “Unit-ish” golden tests (baseline; CI-friendly)

Goal: validate logic without triggering permissions.

Pattern:

1. Put most logic in pure handlers (transformations, parsing, planning).
2. Keep side effects (Apple Events, file system writes, UI) behind thin wrappers.
3. Execute small test scripts via `osascript -s s`, capture stdout, and compare against an expected file.

This is what `./scripts/test_unit.sh` does in the template.

### B) Integration tests via Apple Events (self-hosted runners)

Goal: validate the behavior of a target app via its dictionary.

Constraints:

- Requires **Automation / Apple Events** permission (TCC).
- On hosted CI, permission prompts often cannot be clicked, so runs may hang or fail.

Best practice:

- Run integration tests only on a dedicated dev machine or a self-hosted runner with permissions provisioned.
- Add explicit timeouts and *wait for state* loops.

### C) UI scripting (last resort)

UI scripting is brittle and increasingly restricted.

- It depends on window focus, timing, UI hierarchy, localization, and OS/app updates.
- Enterprise provisioning is tightening: Apple’s public TCC profile schema indicates that granting Accessibility via configuration profile is **deprecated as of macOS 26.2** and **will be removed in macOS 27.0**.

If you must do UI scripting:

- Prefer element existence polling with timeouts over fixed `delay`.
- Use a dedicated user account and a stable desktop configuration.

Example polling pattern (System Events UI scripting):

```applescript
on wait_for_window(appName, windowName, timeoutSeconds)
    set deadline to (current date) + timeoutSeconds
    tell application "System Events" to tell process appName
        repeat until (current date) > deadline
            if (exists window windowName) then return true
            delay 0.1
        end repeat
    end tell
    return false
end wait_for_window
```

## 4) TCC / Automation permissions (engineering playbook)

### Understand “who” is prompting

Automation permissions are evaluated for a **sender → receiver** pairing.

- If you run AppleScript from Terminal, the *sender identity* is often **Terminal**.
- If you run from a CI agent, the sender is the runner’s controlling process.

This matters because approvals are cached and drift across machines.

### Stable sender identity (for teams)

For long-lived automation, consider moving execution behind a stable, signed identity:

- **Applet**: compile a script to a `.app` and run it as an application (stable bundle ID).
- **Helper app**: a minimal Swift/Cocoa app using `NSUserAppleScriptTask` to run user scripts.

`osacompile` uses the output filename extension to decide packaging:

- `.app` → bundled applet/droplet
- `.scptd` → bundled compiled script

### Resetting / recovering permissions

`tccutil` can reset privacy database decisions:

```sh
# Reset Apple Events permissions for a specific sender app (example: Terminal)
tccutil reset AppleEvents com.apple.Terminal

# Reset all TCC decisions for a sender app (disruptive)
tccutil reset All com.apple.Terminal
```

Finding bundle identifiers:

```sh
# Ask LaunchServices via AppleScript
osascript -e 'id of app "Google Chrome"'

# Or via lsappinfo (name must match)
lsappinfo info -only bundleid "Google Chrome"
```

### Provisioning permissions at scale (MDM / PPPC)

If you control test machines, PPPC configuration profiles are the supported way to pre-approve Automation permissions.

Apple’s public TCC profile schema (`com.apple.TCC.configuration-profile-policy`) includes AppleEvents-specific fields such as:

- `AEReceiverIdentifier`
- `AEReceiverIdentifierType` (`bundleID` or `path`)
- `AEReceiverCodeRequirement`

This is the mechanism used to pre-authorize a sender to control a receiver.

## 5) CI/CD guidance for macOS runners

### Hosted macOS runners

Treat hosted runners as “compile + unit tests” only:

- `osacompile` compile gates
- unit-ish golden tests that do not send Apple events and do not require UI permissions

### Self-hosted runners

Run integration/UI automation only on self-hosted runners:

- Ensure a GUI session is available (many UI automations require it).
- Provision TCC/Automation permissions up front (ideally via MDM/PPPC).
- Pin OS + target app versions; add an explicit qualification pass on OS upgrades.

A common split pipeline:

- PR checks: compile + unit tests
- Nightly / release: integration suite on self-hosted runners

## 6) Version sensitivity and forward-looking notes

- macOS point releases can break assumptions. Keep `.applescript` sources and maintain a recompile pipeline.
- macOS 26.4 introduced a Script Editor regression for some older compiled AppleScripts (errOSADataFormatObsolete / -1758). A practical workaround reported publicly is to open and re-save in Script Debugger to recompile to a modern format.

## 7) Source pointers (selected)

These sources were used to ground concrete behaviors and commands:

- Codex skills + optional `agents/openai.yaml`: https://developers.openai.com/codex/skills
- Agent Skills specification (SKILL.md constraints, progressive disclosure): https://agentskills.io/specification
- `osascript(1)` man page (output modifiers `-s s` / `-s o`): https://leancrew.com/all-this/man/man1/osascript.html
- `osacompile(1)` man page (output packaging based on `.app` / `.scptd`): https://leancrew.com/all-this/man/man1/osacompile.html
- Script Editor User Guide: Track events / dictionaries:
  - https://support.apple.com/guide/script-editor/track-events-scpedt1134/mac
  - https://support.apple.com/guide/script-editor/view-an-apps-scripting-dictionary-scpedt1126/mac
- Apple Platform Deployment: PPPC overview: https://support.apple.com/guide/deployment/privacy-preferences-policy-control-payload-dep38df53c2a/web
- Apple device-management TCC schema (AppleEvents fields; Accessibility deprecation note): https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.TCC.configuration-profile-policy.yaml
- `tccutil` syntax reference: https://ss64.com/mac/tccutil.html
- NSAppleEvents usage description discussion (historical but still operationally relevant): https://indiestack.com/2018/08/apple-events-usage-description/
- macOS 26.4 Script Editor regression write-up: https://tidbits.com/2026/03/27/macos-26-4s-script-editor-wont-open-some-older-applescripts/
