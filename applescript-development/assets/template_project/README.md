# AppleScript Automation Project (template)

This template is designed for **repeatable AppleScript development** and **CI-friendly tests**.

## Commands

```sh
./scripts/compile.sh
./scripts/policy_scan.sh --src ./src
./scripts/test_unit.sh
./scripts/run.sh -- arg1 arg2
```

## Optional: integration tests in disposable macOS VMs

If you need Apple Events / UI automation tests that should not touch real user data, run them inside a
disposable VM cloned per run (requires Tart on the host):

```sh
./scripts/test_integration_vm_tart.sh --base <golden-vm-or-image-ref>

# Or rely on auto-selection (prefer an existing local VM, else download the default image)
./scripts/test_integration_vm_tart.sh
```

## Layout

- `src/`: plain-text `.applescript` sources (commit these)
- `build/`: compiled `.scpt` outputs (generated; ignored)
- `tests/unit/`: unit-ish tests (compiled and executed via `osascript -s s`)
- `tests/integration/`: integration tests (typically VM-only)
- `tests/ui/`: UI scripting tests (VM-only; last resort)
- `.github/workflows/applescript-ci.yml`: compile + unit tests (safe for hosted CI)

Integration/UI tests are intentionally not enabled by default.
