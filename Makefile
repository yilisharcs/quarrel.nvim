.PHONY: doc
doc:
	nvim --clean --headless -l scripts/docgen.lua

.PHONY: repro
repro:
	nvim --clean -u scripts/repro.lua

.PHONY: check
check: lint format

.PHONY: lint
lint:
	VIMRUNTIME=$$(nvim --clean --headless --cmd 'lua io.stdout:write(vim.env.VIMRUNTIME)' -c 'q') \
	lua-language-server --check . --checklevel=Hint

.PHONY: format
format:
	stylua .

.PHONY: test
test:
	nvim --clean --headless -l tests/run.lua
