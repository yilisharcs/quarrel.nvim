-- minimal reproduction. run with:
--      `nvim --clean -u repro.lua`

-- leave no traces!!
vim.o.swapfile = false

-- add project root path to runtimepath
local here = debug.getinfo(1, "S").source
local no_at = here:sub(2)
local abs_here_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(no_at)))
vim.o.rtp = abs_here_dir .. "," .. vim.o.rtp

-- redirect database to repro_dir
local repro_dir = vim.fs.joinpath(abs_here_dir, ".repro")
vim.fn.mkdir(repro_dir, "p")
---@diagnostic disable-next-line: missing-fields
require("quarrel").setup({
        database = vim.fs.joinpath(abs_here_dir, ".repro/quarrel.msgpack"),
})
