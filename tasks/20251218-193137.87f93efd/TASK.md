---
status: OPEN
priority: 100
tags: [bug]
---

# Fix trailing error in msgpack

Error in VimEnter Autocommands for "*":
Lua callback: ...s/.config/nvim/pack/dev/opt/quarrel.nvim/lua/quarrel.lua:34: trailing data in msgpack string
stack traceback:
	[C]: in function 'decode'
	...s/.config/nvim/pack/dev/opt/quarrel.nvim/lua/quarrel.lua:34: in function '_get_arglist_database'
	...s/.config/nvim/pack/dev/opt/quarrel.nvim/lua/quarrel.lua:41: in function 'argread'
	...ts/github.com/yilisharcs/quarrel.nvim/plugin/quarrel.lua:50: in function <...ts/github.com/yilisharcs/quarrel.nvim/plugin/quarrel.lua:48>
