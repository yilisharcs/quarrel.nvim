set shell               := ["nu", "-c"] # for single-line execution
set script-interpreter  := ["nu"]       # for bundled execution

doc:
        nvim --headless -u NONE -l scripts/doc.lua

repro:
        nvim --clean -u scripts/repro.lua

check: lint format

lint:
        lua-language-server --check . --checklevel=Hint

format:
        stylua .


test:
        nvim --clean --headless -l tests/run.lua
