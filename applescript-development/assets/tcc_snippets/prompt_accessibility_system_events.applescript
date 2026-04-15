(***
Prompt Accessibility approval for System Events.

This performs a minimal UI-scripting action (a single key press).
If System Events is not allowed under Privacy & Security > Accessibility, macOS typically prompts.

Notes:
- This is intended to be run inside a disposable VM while provisioning a golden image.
- UI scripting is inherently brittle; keep it VM-only when possible.
***)

tell application "System Events"
    key code 123
end tell
