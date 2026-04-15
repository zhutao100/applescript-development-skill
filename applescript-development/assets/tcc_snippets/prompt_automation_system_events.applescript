(***
Prompt Automation (Apple Events) approval for the sender process.

Run this from the identity you intend to use for automation (e.g., Terminal, your CI runner app).
It sends Apple Events to System Events, which should trigger the Automation prompt if not already approved.

Notes:
- This is intended to be run inside a disposable VM while provisioning a golden image.
- It is safe but may require clicking "Allow" in the prompt.
***)

tell application "System Events"
    get name of every process
end tell
