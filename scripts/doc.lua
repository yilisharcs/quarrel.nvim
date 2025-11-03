package.path = "./vendor/?.lua" .. ";" .. "./vendor/?/init.lua" .. package.path
require("mini.doc").generate({ "lua/quarrel.lua" }, "doc/quarrel.nvim.txt", {})
