_default:

# luarocks target
install:
	cp -r lua	$(INST_LUADIR)
	# cp -r ftplugin	$(INST_PREFIX)
	cp -r plugin	$(INST_PREFIX)
	#
	cp -r doc	$(INST_PREFIX)
	cp LICENSE	$(INST_PREFIX)/doc/LICENSE
	cp README.md	$(INST_PREFIX)/doc/README.md

.PHONY: doc watch_entr watch_doc
ARGS   := --headless -u NONE
Q_LUA  ?= $(HOME)/Projects/github.com/yilisharcs/quarrel.nvim/lua/
Q_DIR  ?= $(HOME)/.local/share/nvim/quarrel
Q_FILE ?= $(Q_DIR)/arglists.msgpack

doc:
	@nvim $(ARGS) -l scripts/doc.lua

doc_watch:
	@find $(Q_LUA) -name "*.lua" | entr -cs "make doc > /dev/null"

entr:
	@echo $(Q_FILE) | entr -cs "nvim $(ARGS) -l scripts/entr.lua $(Q_FILE)"
