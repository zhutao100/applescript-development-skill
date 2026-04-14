# AppleScript Development Skills (macOS 15 / macOS 26+)

This repository packages an **Agent Skills / Codex Skills** bundle for **reliable AppleScript automation development and testing** on **modern macOS** (macOS 15 “Sequoia”, macOS 26 “Tahoe”, and forward).

The primary deliverable is the skill folder:

- [`applescript-development/`](./applescript-development/) — step-by-step workflow plus **ready-to-run scripts** and **ready-to-install assets** for scaffolding, building, and testing `.applescript` projects.

## Install

### Option A: Repo-scoped (recommended for a specific project)

Copy or symlink the skill folder into your repo’s `.agents/skills/`:

```sh
mkdir -p .agents/skills
cp -R applescript-development .agents/skills/
# or: ln -s "$(pwd)/applescript-development" .agents/skills/applescript-development
```

### Option B: User-scoped (available everywhere)

```sh
mkdir -p ~/.agents/skills
cp -R applescript-development ~/.agents/skills/
```

Codex will discover the skill automatically; restart Codex if it doesn’t show up.

## Quick start (scaffold a reliable AppleScript project)

From the destination repository (or an empty folder), run:

```sh
/path/to/applescript-development/scripts/install_template.sh --dest .
```

This installs a small project layout with:

- `src/` plain-text `.applescript` sources
- `scripts/` build + test helpers
- `tests/unit/` unit-ish golden-output tests (CI-friendly)
- optional `.github/workflows/ci.yml` for **compile + unit tests**

## What’s inside

- **`applescript-development/SKILL.md`**: executive workflow for agents.
- **`applescript-development/references/REFERENCE.md`**: deeper details (TCC/Automation, CI strategies, UI scripting reliability, signing/entitlements pointers).
- **`applescript-development/scripts/`**: ready-to-run utilities agents can invoke directly.
- **`applescript-development/assets/`**: ready-to-copy templates installed by the scripts.

## License

MIT — see [`LICENSE`](./LICENSE).
