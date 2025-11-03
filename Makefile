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

.PHONY: doc
doc:
	@nvim --headless -u NONE -l scripts/doc.lua
