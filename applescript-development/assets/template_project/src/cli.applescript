(***
cli.applescript

Entry point executed by `osascript`.
Return structured values so tests can assert deterministically using `osascript -s s`.
***)

on run argv
    if (count of argv) = 0 then
        return {"ok", true, "greeting", greet("world"), "info", normalize_argv({})}
    end if

    set name to item 1 of argv
    return {"ok", true, "greeting", greet(name), "info", normalize_argv(argv)}
end run
