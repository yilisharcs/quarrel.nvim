package.path = "./vendor/?.lua" .. ";" .. "./vendor/?/init.lua" .. package.path

local minidoc = require("mini.doc")
minidoc.setup()

minidoc.generate({
        "lua/quarrel.lua",
        "plugin/quarrel.lua",
}, "doc/quarrel.nvim.txt", {})
