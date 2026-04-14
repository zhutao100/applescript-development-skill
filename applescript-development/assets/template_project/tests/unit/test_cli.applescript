(***
test_cli.applescript

A unit-ish test script compiled together with src/lib.applescript.
Returns a deterministic value for golden output comparison.
***)

on run argv
    return {"case", "greet", "out", greet("Ada"), "info", normalize_argv({"Ada"})}
end run
