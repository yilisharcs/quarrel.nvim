if vim.g.loaded_quarrel == 1 then return end
vim.g.loaded_quarrel = 1

local qpath = vim.fs.joinpath(vim.fn.stdpath("data"), "quarrel")
if vim.fn.isdirectory(qpath) == 0 then vim.fn.mkdir(qpath) end

local database = vim.fs.joinpath(qpath, "arglists.msgpack")

---@toc_entry CONFIGURATION
---@tag Quarrel-configuration
---@class quarrel.Config
---
---@field database string Path to the database file where arglists are stored.
---     Default: `vim.fn.stdpath("data") .. "/quarrel/arglists.msgpack"`
---
---@field keymaps boolean If `true`, enables default keymaps for navigating the
---     arglist. See |Quarrel-keymaps|.
---     Default: `false`
---
---@usage >lua
---     vim.g.quarrel = {
---             database = vim.env.HOME .. "/Documents",
---             keymaps = true,
---     }
--- <
local DEFAULTS = {
        database = database,
        keymaps = false,
}

vim.g.quarrel = vim.tbl_deep_extend("force", DEFAULTS, vim.g.quarrel or {})

---@tag Quarrel-keymaps
---@text
---
if vim.g.quarrel.keymaps then
        vim.keymap.set("n", "<leader>a", function()
                vim.cmd("$argadd")
                vim.cmd.argdedup()
        end, { desc = "Add current file to arglist" })
        -- stylua: ignore start
        vim.keymap.set("n", "<leader>h", function() vim.cmd.argument({ count = 1 }) end, { desc = "Arg file 1" })
        vim.keymap.set("n", "<leader>j", function() vim.cmd.argument({ count = 2 }) end, { desc = "Arg file 2" })
        vim.keymap.set("n", "<leader>k", function() vim.cmd.argument({ count = 3 }) end, { desc = "Arg file 3" })
        vim.keymap.set("n", "<leader>l", function() vim.cmd.argument({ count = 4 }) end, { desc = "Arg file 4" })
        vim.keymap.set("n", "<leader>;", function() vim.cmd.argument({ count = 5 }) end, { desc = "Arg file 5" })
        -- stylua: ignore end
end

local augroup = vim.api.nvim_create_augroup("Quarrel", { clear = true })

vim.api.nvim_create_autocmd({ "VimEnter" }, {
        desc = "Setup arglist on enter",
        group = augroup,
        callback = function() require("quarrel").on_enter() end,
})

vim.api.nvim_create_autocmd({ "DirChanged" }, {
        desc = "Load arglist",
        group = augroup,
        callback = function() require("quarrel").load() end,
})

vim.api.nvim_create_autocmd({ "DirChangedPre", "VimLeavePre" }, {
        desc = "Save arglist",
        group = augroup,
        callback = function() require("quarrel").save() end,
})

vim.api.nvim_create_autocmd({ "QuitPre" }, {
        desc = "Ignore arglist error E173",
        group = augroup,
        callback = function()
                vim.schedule(function()
                        if not vim.v.errmsg:match("E173:") then return end
                        -- stylua: ignore
                        vim.api.nvim_set_hl(0, "ErrorMsg", { fg = "bg", bg = "bg" })
                        vim.cmd("noau qall")
                end)
        end,
})
