(***
lib.applescript

Keep most logic here: pure handlers that are deterministic and testable.
Avoid side effects (Apple Events, UI scripting, filesystem writes) in this file.

Note on test stability:
- Golden tests compare `osascript -s s` output.
- Prefer lists over records for golden outputs because record key order can be version-dependent.
***)

on normalize_argv(argv)
    return {"argc", (count of argv), "argv", argv}
end normalize_argv

on greet(name)
    return "hello, " & name & "."
end greet
