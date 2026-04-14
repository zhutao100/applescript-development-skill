# AppleScript Automation Project (template)

This template is designed for **repeatable AppleScript development** and **CI-friendly tests**.

## Commands

```sh
./scripts/compile.sh
./scripts/test_unit.sh
./scripts/run.sh -- arg1 arg2
```

## Layout

- `src/`: plain-text `.applescript` sources (commit these)
- `build/`: compiled `.scpt` outputs (generated; ignored)
- `tests/unit/`: unit-ish tests (compiled and executed via `osascript -s s`)
- `.github/workflows/applescript-ci.yml`: compile + unit tests (safe for hosted CI)

Integration/UI tests are intentionally not enabled by default.
