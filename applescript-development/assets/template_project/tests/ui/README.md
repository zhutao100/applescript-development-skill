# UI scripting tests

UI scripting (via System Events / Accessibility) is the least deterministic automation layer:

- sensitive to focus, timings, localization, and UI hierarchy changes
- typically blocked by unattended TCC prompts

If you must do UI scripting, run it only inside a disposable VM (or a dedicated automation machine) and
collect **diagnostic artifacts** (screenshots, window lists, UI tree dumps).
