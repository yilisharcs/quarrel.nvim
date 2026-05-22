--- *quarrel.nvim.txt*                   Automagically manage project-local arglists
---
--- Apache License 2.0 Copyright (c) 2025-2026 yilisharcs

---                               Table of Contents
---
---@toc

---@toc_entry INTRODUCTION
---@tag Quarrel
---@tag Quarrel-intro
---@text
--- *quarrel.nvim* intends to fix a persistent issue in file navigation: alternate
--- buffers can't cope with multiple files and global marks don't remember cursor
--- position. This plugin leverages the built-in arglist to automatically manage
--- these multiple files. Whenever you change directories, it'll save the arglist
--- of the previous directory and load the next one's.
---
--- # Setup ~
---
--- This plugin works out of the box via 'runtimepath'. It can be configured with
--- `vim.g.quarrel` in `init.lua`, and provides a global Lua table for scripting. You
--- can call `require("quarrel").setup()` to refresh all internal side-effects.
---
--- See |Quarrel-configuration| for `config` structure and default values.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.quarrel_disable` (globally) to `true`.

-- ## MODULE DEFINITION ##

local Quarrel = {}
local H = {}

--- Module setup.
---
--- @param config quarrel.Config|nil Optional overrides.
function Quarrel.setup(config)
        if vim.version.cmp(vim.version(), { 0, 12, 0 }) < 0 then
                vim.notify("quarrel.nvim requires Neovim 0.12+", vim.log.levels.ERROR)
                return
        end

        -- export module
        _G.Quarrel = Quarrel

        -- use local var to avoid de/reserialization via lua-vim bridge roundtrip
        local validated_config = H.setup_config(config or vim.g.quarrel)
        H.apply_config(validated_config)

        -- reload arglist on config reload
        if vim.v.vim_did_enter == 1 then H.init_arglist() end
end

---@toc_entry CONFIGURATION
---@tag Quarrel-configuration
---@class quarrel.Config
---
---@field database string Path to the database file where arglists are stored.
---     Default: `"$XDG_DATA_HOME/nvim/quarrel/quarrel.msgpack"`
---
---@field mappings table Module mappings. Use `''` (empty string) to disable one.
---
---@field mappings.add string Add current file to arglist.
---     Default: `"<leader>a"`
---
---@field mappings.edit string Edit the arglist.
---     Default: `"<leader>e"`
---
---@field mappings.arg1 string Go to arg file 1. Default: `"<leader>h"`
---@field mappings.arg2 string Go to arg file 2. Default: `"<leader>j"`
---@field mappings.arg3 string Go to arg file 3. Default: `"<leader>k"`
---@field mappings.arg4 string Go to arg file 4. Default: `"<leader>l"`
---@field mappings.arg5 string Go to arg file 5. Default: `"<leader>;"`
---
---@usage >lua
---     vim.g.quarrel = {
---             database = `vim.fs.joinpath(vim.env.HOME, ".quarrel.msgpack")`,
---             mappings = {
---                     add = "<leader>qa",
---                     edit = "<leader>qe",
---             },
---     }
--- <
Quarrel.config = {
        database = vim.fs.joinpath(vim.fn.stdpath("data"), "quarrel", "quarrel.msgpack"),
        mappings = {
                add = "<leader>a",
                edit = "<leader>e",
                arg1 = "<leader>h",
                arg2 = "<leader>j",
                arg3 = "<leader>k",
                arg4 = "<leader>l",
                arg5 = "<leader>;",
        },
}

--- Save current arglist to database.
---
--- @param config quarrel.Config|nil Optional overrides.
function Quarrel.save(config)
        if H.is_disabled() then return end
        local active_config = H.get_config(config)

        local cwd = vim.uv.cwd()
        if not cwd then return end

        local normalized = {}
        local raw_argv = vim.fn.argv()
        ---@cast raw_argv string[]
        for _, path in ipairs(raw_argv) do
                local file = H.is_eligible(path)
                if file then table.insert(normalized, file) end
        end

        local db = H.read_db(active_config.database)
        if #normalized > 0 then
                db[cwd] = normalized
        else
                db[cwd] = nil -- prune empty
        end

        H.write_db(active_config.database, db)
end

--- Load project-local arglist from database.
---
--- @param config quarrel.Config|nil Optional overrides.
function Quarrel.load(config)
        if H.is_disabled() then return end
        local active_config = H.get_config(config)

        local cwd = vim.uv.cwd()
        if not cwd then return end

        -- always clear the list
        vim.cmd("%argdelete")

        local db = H.read_db(active_config.database)
        local arglist = db[cwd]
        if not arglist or #arglist == 0 then return end

        for _, path in ipairs(arglist) do
                local file = H.is_eligible(path)
                if file then vim.cmd("$argadd " .. vim.fn.fnameescape(file)) end
        end
end

--- Open arglist editor.
---
--- @param config quarrel.Config|nil Optional overrides.
function Quarrel.edit(config)
        if H.is_disabled() then return end

        local cwd = vim.uv.cwd()
        if not cwd then return end

        -- editor toggle
        if H.editor_buf and vim.api.nvim_buf_is_valid(H.editor_buf) then
                vim.api.nvim_buf_delete(H.editor_buf, { force = true })
                H.editor_buf = nil
                return
        end

        local buf = vim.api.nvim_create_buf(false, true)
        local win = vim.api.nvim_open_win(buf, true, { split = "below" })
        H.editor_buf = buf

        vim.api.nvim_buf_set_name(buf, "quarrel://" .. cwd)
        vim.api.nvim_set_option_value("filetype", "quarrel", { buf = buf })
        vim.api.nvim_set_option_value("syntax", "gitignore", { buf = buf })
        vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
        vim.api.nvim_set_option_value("number", true, { win = win })
        vim.api.nvim_set_option_value("relativenumber", false, { win = win })

        local raw_argv = vim.fn.argv()
        ---@cast raw_argv string[]
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, raw_argv)
        vim.api.nvim_set_option_value("modified", false, { buf = buf })

        vim.api.nvim_create_autocmd("BufWriteCmd", {
                buffer = buf,
                callback = function()
                        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

                        local arglist = {}
                        for _, line in ipairs(lines) do
                                local file = H.is_eligible(vim.trim(line))
                                if file then table.insert(arglist, vim.fn.fnameescape(file)) end
                        end

                        -- always clear the list
                        vim.cmd("%argdelete")
                        if #arglist > 0 then
                                for _, path in ipairs(arglist) do
                                        vim.cmd("$argadd " .. path)
                                end
                        end
                        Quarrel.save()

                        vim.api.nvim_set_option_value("modified", false, { buf = buf })
                end,
        })
end

-- ## HELPER DATA ##

-- Module default config
H.default_config = vim.deepcopy(Quarrel.config)

-- ## HELPER FUNCTIONALITY ##

---@private
--- Setup configuration.
---
--- @param config quarrel.Config|nil Raw configuration table.
---
--- @return quarrel.Config # Validated and merged configuration.
H.setup_config = function(config)
        vim.validate({ config = { config, "table", true } })
        config = vim.tbl_deep_extend("force", vim.deepcopy(H.default_config), config or {})

        vim.validate({
                database = { config.database, "string" },
                mappings = { config.mappings, "table" },
                ["mappings.add"] = { config.mappings.add, "string" },
                ["mappings.edit"] = { config.mappings.edit, "string" },
                ["mappings.arg1"] = { config.mappings.arg1, "string" },
                ["mappings.arg2"] = { config.mappings.arg2, "string" },
                ["mappings.arg3"] = { config.mappings.arg3, "string" },
                ["mappings.arg4"] = { config.mappings.arg4, "string" },
                ["mappings.arg5"] = { config.mappings.arg5, "string" },
        })

        return config
end

---@private
--- Apply configuration side-effects.
---
--- @param config quarrel.Config Validated configuration table.
H.apply_config = function(config)
        Quarrel.config = config
        vim.g.quarrel = config
        H.create_autocommands()
        H.create_usercommands()
        H.create_mappings(config)
end

---@private
--- Get current configuration.
---
---@param config quarrel.Config|nil Optional overrides for this call.
---
---@return quarrel.Config
H.get_config = function(config)
        return vim.tbl_deep_extend("force", H.default_config, vim.g.quarrel or {}, config or {})
end

---@private
--- Check if module is disabled.
---
---@return boolean # True if disabled globally.
H.is_disabled = function() return vim.g.quarrel_disable == true end

---@private
--- Create module autocommands.
H.create_autocommands = function()
        local group = vim.api.nvim_create_augroup("Quarrel", { clear = true })

        vim.api.nvim_create_autocmd({ "DirChangedPre", "VimLeavePre" }, {
                group = group,
                desc = "Save project-local arglist",
                callback = function() Quarrel.save() end,
        })

        vim.api.nvim_create_autocmd("DirChanged", {
                group = group,
                desc = "Load project-local arglist",
                callback = function() Quarrel.load() end,
        })

        vim.api.nvim_create_autocmd({ "VimEnter" }, {
                desc = "Setup arglist on enter",
                group = group,
                callback = function() H.init_arglist() end,
        })
end

---@toc_entry COMMANDS
---@tag Quarrel-commands
---@text
---
--- `:Quarrel`
---     Opens a special buffer to edit the current arglist.

---@private
--- Create module user commands.
H.create_usercommands = function()
        vim.api.nvim_create_user_command(
                "Quarrel",
                function() Quarrel.edit() end,
                { desc = "Edit the arglist" }
        )
end

---@private
--- Create module mappings.
---
--- @param config quarrel.Config Validated configuration table.
H.create_mappings = function(config)
        local m = config.mappings
        local map = function(lhs, rhs, desc)
                if lhs == "" then return end
                vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
        end

        map(m.add, function()
                if H.is_eligible(vim.fn.expand("%:p")) then vim.cmd("$argadd | argdedup") end
        end, "Add current file to the arglist")
        -- stylua: ignore start
        map(m.edit, function() Quarrel.edit() end, "Open the arglist editor")
        map(m.arg1, function() pcall(vim.cmd.argument, { count = 1 }) end, "Arg file 1")
        map(m.arg2, function() pcall(vim.cmd.argument, { count = 2 }) end, "Arg file 2")
        map(m.arg3, function() pcall(vim.cmd.argument, { count = 3 }) end, "Arg file 3")
        map(m.arg4, function() pcall(vim.cmd.argument, { count = 4 }) end, "Arg file 4")
        map(m.arg5, function() pcall(vim.cmd.argument, { count = 5 }) end, "Arg file 5")
        -- stylua: ignore end
end

---@private
--- Read data from database.
---
--- @param path string File path to read from.
H.read_db = function(path)
        if vim.fn.filereadable(path) == 0 then return {} end

        local fp = io.open(path, "rb")
        if not fp then return {} end
        local data = fp:read("*all")
        fp:close()

        if #data == 0 then return {} end

        local ok, db = pcall(vim.mpack.decode, data)
        return ok and db or {}
end

---@private
--- Write data to database.
---
--- @param path string File path to write to.
--- @param data table Data to encode and write.
H.write_db = function(path, data)
        local dir = vim.fs.dirname(path)
        if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end

        -- NOTE: `vim.mpack.encode` can't serialize functions, userdata, and
        --       coroutines. it's probably not relevant to our usecase but I
        --       believe that it's better to be safe than sorry.
        local ok, packed = pcall(vim.mpack.encode, data)
        if not ok then return end

        local fp = io.open(path, "wb")
        if not fp then return end
        fp:write(packed)
        fp:close()
end

---@private
--- Initialize arglist from startup arguments or database.
---
--- Filters out any arguments that evaluate to a directory.
H.init_arglist = function()
        local argf_no_dir = {}
        for _, path in ipairs(vim.v.argf) do
                local file = H.is_eligible(path)
                if file then table.insert(argf_no_dir, file) end
        end

        if #argf_no_dir == 0 then
                Quarrel.load()
                return
        end

        -- always clear the list
        vim.cmd("%argdelete")
        for _, path in ipairs(argf_no_dir) do
                vim.cmd("$argadd " .. vim.fn.fnameescape(path))
        end
end

---@private
--- Check if a path is eligible for the arglist.
---
--- @param path string Filepath to check.
---
--- @return string|nil # The absolute path if eligible, nil otherwise.
H.is_eligible = function(path)
        if type(path) ~= "string" or path == "" then return nil end

        -- collapse redundant separators and resolve relative paths
        local abspath = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
        if vim.fn.isdirectory(abspath) == 1 then return nil end

        -- stylua: ignore
        local roots = vim.iter({
                vim.env.TMPDIR,
                "/tmp/",
                "/var/tmp/"
        })
                -- discard $TMPDIR if unset
                :filter(function(it) return it and it ~= "" end)
                :map(function(it) return vim.fs.normalize(vim.fn.fnamemodify(it, ":p")) end)
                :totable()

        if vim.iter(roots):any(function(it) return vim.startswith(abspath, it) end) then
                return nil
        end

        return abspath
end

return Quarrel

-- vim: textwidth=83
