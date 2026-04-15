# Integration tests

Integration tests are for Apple Events-driven validation against a **real target app** (Mail, Safari, Finder, etc.).

Because modern macOS automation requires TCC approvals (Automation / Apple Events, and often Accessibility for UI scripting),
these tests are usually run in a **disposable macOS VM cloned per run**.

## Suggested workflow

1. Build/maintain a **golden VM** with:
   - a dedicated test user (no personal Apple ID / iCloud)
   - seeded synthetic fixtures
   - required Automation/Accessibility prompts pre-approved
2. Run `./scripts/test_integration_vm_tart.sh --base <golden-vm>`
3. Collect artifacts under `./artifacts/vm/...` (logs, screenshots, fixture diffs).

Place your integration test scripts in this directory and have `scripts/test_integration.sh` invoke them.
