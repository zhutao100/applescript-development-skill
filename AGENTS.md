# Agent guide for this repository

## Purpose

This repo is an **agent skill bundle**. The end users are agent runtimes (Codex CLI, IDE agents, etc.) that load `SKILL.md` metadata eagerly and load the full instructions and resources lazily.

Your job when modifying this repo is to keep the skill:

1. **Discoverable** (good `name` / `description` triggers).
2. **Context-efficient** (progressive disclosure).
3. **Actionable** for agents (scripts + assets that can be executed/copied without manual editing).

## Repo layout

```
LICENSE
README.md
AGENTS.md
applescript-development/
  SKILL.md
  agents/openai.yaml
  scripts/
  references/
  assets/
```

## Editing rules

- Keep `applescript-development/SKILL.md` **under ~500 lines** and focused on **execution steps**.
- Put deep details in **one** reference doc: `applescript-development/references/REFERENCE.md`.
- Avoid multi-hop reference chains. `SKILL.md` may link to `references/REFERENCE.md`, but references should not link onward to more local files.
- Prefer **ready-to-run scripts** over long copy/paste snippets when the workflow can be automated.

## Expected workflows to validate after changes

1. **Skill spec conformance**
   - `applescript-development/SKILL.md` YAML frontmatter:
     - `name` matches the directory name exactly.
     - `description` clearly says when to use and when not to use.
   - No nested reference chains.

2. **Template installer works**
   - In a temp folder:
     - Run `applescript-development/scripts/install_template.sh --dest .`
     - Run `./scripts/compile.sh`
     - Run `./scripts/test_unit.sh`

3. **Scripts are portable**
   - Scripts must run with system Bash and `/usr/bin/osascript` + `/usr/bin/osacompile`.
   - Optional helpers may use `python3`, but must fail with a clear message if missing.

## When adding new content

- If it is **executed** (build/test/install), add it to `applescript-development/scripts/`.
- If it is **copied into user repos**, add it to `applescript-development/assets/` and wire it into an installer script.
- If it is explanatory or policy content, put it in `references/REFERENCE.md`.

## Safety / side effects

- Do not add scripts that:
  - reset TCC/privacy databases by default,
  - send Apple events or UI events by default,
  - modify system settings.

Any such operations must be explicit, opt-in, and clearly documented.
