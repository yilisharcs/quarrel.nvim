set shell               := ["nu", "-c"] # for single-line execution
set script-interpreter  := ["nu"]       # for bundled execution

doc:
        nvim --headless -u NONE -l scripts/doc.lua

repro:
        nvim --clean -u scripts/repro.lua
