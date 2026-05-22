package.path = "./vendor/mini.doc/lua/?.lua;" .. package.path

local minidoc = require("mini.doc")
minidoc.setup()

minidoc.generate({
        "lua/quarrel.lua",
}, "doc/quarrel.nvim.txt", {})
