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
--- buffers can't cope with multiple files and global marks are neither unlimited
--- nor project-local. This plugin leverages the built-in |arglist| to automatically
--- manage these multiple files. Whenever you change directories, it'll save the
--- arglist of the previous directory and load the next one's.
---
--- # Design ~
---
--- ThePrimeagen's Harpoon is what introduced me to the concept of project-local
--- marks. After some time -- and a bug that I couldn't track down which prevented
--- me from embracing the idea completely -- I decided to simplify my init.lua and
--- use global marks instead, and even opened an issue on GitHub with a snippet of
--- code that I'd used for a long time, hoping that it would be upstreamed:
---
--- `Update global mark position on BufLeave, VimLeavePre`
---     https://github.com/neovim/neovim/issues/36358
---
--- I was quickly disabused of the idea that global marks should remember the
--- cursor position. They serve a different purpose. I dislike that purpose, but
--- it is a purpose nonetheless. I decided then that writing this plugin could be
--- a learning experience in leveraging native solutions over custom special files
--- and json. Thus, it was born: a minimal wrapper around the |arglist| that stays
--- out of the way. It maps a directory path to a list of paths and encodes them
--- into msgpack format with |vim.mpack|. This data is held in-memory until you
--- exit Nvim (impossible!!), to mean that this plugin does not support multiple
--- instances writing to the database; the last writer wins.
---
--- This diverged from the original goal. This plugin handles neither remembering
--- the cursor position nor automatically changing directories with heuristics; I
--- recommend using [|MiniMisc|](https://github.com/nvim-mini/mini.misc) with
--- `setup_auto_root()` and `setup_restore_cursor()` enabled for that. This plugin
--- does not external track file changes to update the arglist; I recommend using
--- [yazi.nvim](https://github.com/mikavilpas/yazi.nvim) for that. This plugin
--- also does not provide a picker for the arglist, and will never have one. It
--- will remain minimal.
---
--- # Commands ~
---
---                                                      *:Qedit*
--- :Qedit                  Open a |special-buffer| with 'filetype' quarrel for the
---                         current directory's arglist. Edits, additions,
---                         removals, and shuffles are committed to the cache on
---                         save.
---
---                                                      *:Qolder*
--- :Qolder                 Navigate to an older snapshot in history. Clears the
---                         current |arglist| and replaces it with the previous
---                         snapshot. Note that later snapshots will be pruned if
---                         an older arglist is edited.
---
---                                                      *:Qnewer*
--- :Qnewer                 Navigate to a newer snapshot in history. Clears the
---                         current |arglist| and replaces it with the next
---                         snapshot.
---
--- # Setup ~
---
--- This plugin works out of the box via 'runtimepath'. It can be configured with
--- `vim.g.quarrel` in `init.lua`, and provides a global Lua table for scripting. You
--- can call `require("quarrel").setup()` to refresh all internal side-effects.
---
--- See |Quarrel-configuration| for `config` structure and default values.
---
--- # Tips ~
---
--- Leverage built-in Neovim features to make editing more pleasant:
--- - Edit the |:previous| or |:next| arglist files with `[a` and `a]`.
--- - |:rewind| to the first or jump to the |:last| arglist files with `[A` and `A]`.
--- - Operate on the arglist with |:argdo|.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.quarrel_disable` (globally) to `true`.

-- ################################################################################################
-- #                                                                                              #
-- #                                     MODULE DEFINITION                                        #
-- #                                                                                              #
-- ################################################################################################

local Quarrel = {}
local H = {}

---@toc_entry CONFIGURATION
---@tag Quarrel-configuration
---@class quarrel.Config
---
---@field database string Path to the database file where arglists are stored.
---     Default: `vim.fs.joinpath(vim.fn.stdpath("state"), "quarrel/quarrel.msgpack")`
---
---@field hist_level number Number of history entries to keep per project.
---     Default: `3`
---
---@field notify boolean Whether to automatically echo the arglist on changes.
---     Default: `false`
---
---@field mappings quarrel.Mappings Module mappings. Use `''` (empty string) to
---     disable one.
---
---@usage >lua
---     ---@type quarrel.Opts
---     vim.g.quarrel = {
---             database = vim.fs.joinpath(vim.env.HOME, ".quarrel.msgpack"),
---             hist_level = 10,
---             notify = true,
---             mappings = {
---                     add = "<leader>qa",
---                     edit = "<leader>qe",
---                     older = "<leader>qo",
---                     newer = "<leader>qn",
---             },
---     }
--- <

---@class quarrel.Mappings
---
---@field add string Add current file to arglist.
---     Default: `"<leader>a"`
---
---@field edit string Edit the arglist.
---     Default: `"<leader>e"`
---
---@field older string Go to older arglist.
---     Default: `"<leader>["`
---
---@field newer string Go to newer arglist.
---     Default: `"<leader>]"`
---
---@field arg1 string Go to arg file 1. Default: `"<leader>h"`
---@field arg2 string Go to arg file 2. Default: `"<leader>j"`
---@field arg3 string Go to arg file 3. Default: `"<leader>k"`
---@field arg4 string Go to arg file 4. Default: `"<leader>l"`
---@field arg5 string Go to arg file 5. Default: `"<leader>;"`

---@type quarrel.Config
Quarrel.config = {
        database = vim.fs.joinpath(vim.fn.stdpath("state"), "quarrel/quarrel.msgpack"),
        hist_level = 3,
        notify = false,
        mappings = {
                add = "<leader>a",
                edit = "<leader>e",
                older = "<leader>[",
                newer = "<leader>]",
                arg1 = "<leader>h",
                arg2 = "<leader>j",
                arg3 = "<leader>k",
                arg4 = "<leader>l",
                arg5 = "<leader>;",
        },
}

--- Module setup.
---
--- Merges the provided {config} OR `vim.g.quarrel` with the defaults to establish
--- the active state. This function initializes |autocommand|s, |user-commands|, and
--- |mapping|s. Can be called multiple times to reload settings.
---
---@param config quarrel.Opts? Optional overrides.
function Quarrel.setup(config)
        if vim.version.cmp(vim.version(), { 0, 12, 0 }) < 0 then
                vim.notify(
                        "quarrel.nvim requires Neovim 0.12+",
                        vim.log.levels.ERROR,
                        { title = "quarrel" }
                )
                return
        end

        -- export module
        _G.Quarrel = Quarrel

        -- use local var to avoid de/reserialization via lua-vim bridge roundtrip
        local validated_config = H.setup_config(config or vim.g.quarrel --[[@as quarrel.Opts?]])
        H.apply_config(validated_config)

        -- reload arglist on config reload
        if vim.v.vim_did_enter == 1 then
                H.init_arglist()
        end
end

---@toc_entry PLUGIN API
---@tag Quarrel-api
---@tag Quarrel-API
---@text
--- Public module functions for manual arglist management.
---
--- Functions in this module respect |vim.g.quarrel_disable|. To ensure the arglist
--- is not populated with junk, the plugin only tracks "eligible" files. A path is
--- considered eligible if:
--- - It is not a directory.
--- - It is not located in a temporary directory (e.g., /tmp, /var/tmp).
--- - It is not an empty string.

--- Write current arglist to the in-memory cache.
---
--- Under normal operation, this is handled with |DirChangedPre| (on |:chdir|) and
--- |VimLeavePre| (on |:quit|) |autocommand|s. Call this manually to commit the active
--- arglist to the session state without touching the disk. Changes are appended to
--- the history for the current project.
function Quarrel.write_cache()
        if H.is_disabled() then
                return
        end

        local cwd = vim.uv.cwd()
        if not cwd then
                return
        end

        -- no existing history for cwd? create a fallback table
        local history = Quarrel.cache.db.data[cwd] or { index = 0, entries = {} }
        local normalized = vim.iter(vim.fn.argv()):map(H.is_eligible):totable()

        -- avoid creating empty histories for empty projects
        if #normalized == 0 and #history.entries == 0 then
                return
        end

        -- in-place edit: overwrite current index, never increment
        if history.index > 0 then
                if not vim.deep_equal(normalized, history.entries[history.index]) then
                        history.entries[history.index] = normalized
                end
        else
                table.insert(history.entries, normalized)
                history.index = 1
                Quarrel.cache.db.data[cwd] = history
        end
end

--- Write the in-memory cache to the database file.
---
--- Commits the current state of all project arglists to the msgpack database file.
--- This is handled automatically on |VimLeavePre|.
---
---@param config quarrel.Opts? Optional overrides.
function Quarrel.write_db(config)
        local active_config = H.get_config(config)
        H.write_db_file(active_config.database, Quarrel.cache.db)
end

--- Read project-local arglist from the in-memory cache.
---
--- Under normal operation, this is handled with |DirChanged| (after |:chdir|) and
--- |VimEnter| (on startup) |autocommand|s. Call this manually to sync the active
--- arglist with the stored state for the current directory.
function Quarrel.read()
        if H.is_disabled() then
                return
        end

        local cwd = vim.uv.cwd()
        if not cwd then
                return
        end

        -- always clear the list
        vim.cmd("%argdelete")

        local history = Quarrel.cache.db.data[cwd]
        if not history or #history.entries == 0 then
                return
        end

        local arglist = history.entries[history.index]
        if not arglist or #arglist == 0 then
                return
        end

        vim.iter(arglist):map(H.is_eligible):each(H.argadd)
        H.notify()
end

--- Add a file to the arglist.
---
--- Normalizes the provided {path} to an absolute string before adding it to the
--- end of the arglist. If no {path} is provided, the result of |expand|("%:p") is
--- used. The resulting list is then deduplicated with |:argdedup| and cached.
---
---@param path string? Absolute path to add. Defaults to current file.
function Quarrel.add(path)
        if H.is_disabled() then
                return
        end
        vim.iter({ path or vim.fn.expand("%:p") }):map(H.is_eligible):each(H.argadd)
        vim.cmd.argdedup()
        Quarrel.write_cache()
        H.notify()
end

--- Go to a specific arglist file.
---
--- Internally executes |:argument| with {idx} as the count. Like standard Vim, this
--- uses 1-based indexing. No-op if {idx} is invalid.
---
---@param idx number Arglist index.
function Quarrel.goto_arg(idx)
        if H.is_disabled() then
                return
        end
        pcall(vim.cmd.argument, { count = idx })
end

--- Navigate to the older arglist in history.
function Quarrel.older()
        if H.is_disabled() then
                return
        end

        local cwd = vim.uv.cwd()
        local history = cwd and Quarrel.cache.db.data[cwd]
        if not history then
                return
        end

        local prev_index = history.index
        history.index = math.max(1, history.index - 1)
        if history.index ~= prev_index then
                Quarrel.read()
        end
end

--- Navigate to the newer arglist in history.
function Quarrel.newer()
        if H.is_disabled() then
                return
        end

        local cwd = vim.uv.cwd()
        local history = cwd and Quarrel.cache.db.data[cwd]
        if not history then
                return
        end

        local prev_index = history.index
        history.index = math.min(#history.entries, history.index + 1)
        if history.index ~= prev_index then
                Quarrel.read()
        end
end

--- Toggle the arglist editor.
---
--- Opens a |special-buffer| with 'filetype' quarrel for the current directory's
--- arglist. Edits, additions, removals, and shuffles are written to the cache.
function Quarrel.edit()
        if H.is_disabled() then
                return
        end

        local cwd = vim.uv.cwd()
        if not cwd then
                return
        end

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

        local raw_argv = vim.fn.argv() --[[@as string[] ]]
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, raw_argv)
        vim.api.nvim_set_option_value("modified", false, { buf = buf })

        vim.api.nvim_create_autocmd("BufWriteCmd", {
                buffer = buf,
                callback = function()
                        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

                        local arglist = vim.iter(lines)
                                :map(function(line)
                                        return H.is_eligible(vim.trim(line))
                                end)
                                :totable()

                        -- always clear the list
                        vim.cmd("%argdelete")
                        vim.iter(arglist):each(H.argadd)
                        Quarrel.write_cache()

                        vim.api.nvim_set_option_value("modified", false, { buf = buf })
                end,
        })
end

-- ################################################################################################
-- #                                                                                              #
-- #                                       HELPER DATA                                            #
-- #                                                                                              #
-- ################################################################################################

---@class quarrel.Cache
---
---@field db quarrel.Argdata In-memory database mapping projects to arglists.
---     This field is lazily loaded from the configured database file on first
---     access. Modifications to this table are volatile until manually committed
---     via |Quarrel.write_db()| or automatically on |VimLeavePre|.
---
---     WARNING: Incorrect edits might break the schema and corrupt the database!
---              Don't touch this if you don't know what you're doing.
---
---@usage >lua
---     -- Manually clear the cache for a project
---     Quarrel.cache.db.data["/home/user/my_project"] = nil
---
---     -- Set a new arglist for a project
---     Quarrel.cache.db.data["/home/user/my_project"] = {
---             index = 1,
---             entries = {
---                     {
---                             "/home/user/my_project/lua/foo.lua",
---                             "/home/user/my_project/tests/bar.lua",
---                     }
---             }
---     }
---     -- Don't forget to sync your changes!!
---     Quarrel.read()
--- <
Quarrel.cache = {}

setmetatable(Quarrel.cache, {
        __index = function(self, key)
                if key == "db" then
                        local data = H.read_db_file(H.get_config().database)
                        rawset(self, "db", data)
                        return data
                end
        end,
})

---@private
---@type quarrel.Config
H.default_config = vim.deepcopy(Quarrel.config)

---@private
---@type number?
H.editor_buf = nil

---@private
---@type boolean?
H.is_notify_hijacked = nil

-- ################################################################################################
-- #                                                                                              #
-- #                                   HELPER FUNCTIONALITY                                       #
-- #                                                                                              #
-- ################################################################################################

---@private
--- Setup configuration.
---
---@param config quarrel.Opts? Raw configuration table.
---
---@return quarrel.Config # Validated and merged configuration.
H.setup_config = function(config)
        Quarrel._validate_config(config)

        -- stylua: ignore
        local merged = vim.tbl_deep_extend(
                "force",
                vim.deepcopy(H.default_config),
                config or {}
        ) --[[@as quarrel.Config]]

        return merged
end

---@private
--- This function is exposed so it can be reused by `health.lua`.
--- It is not intended to be used as part of the plugin API.
---
---@param config quarrel.Opts? Raw configuration table.
function Quarrel._validate_config(config)
        vim.validate("config", config, "table", true)
        local c = config or {}

        vim.validate("database", c.database, "string", true)
        vim.validate("hist_level", c.hist_level, "number", true)
        vim.validate("notify", c.notify, "boolean", true)
        vim.validate("mappings", c.mappings, "table", true)

        if c.mappings then
                vim.validate("mappings.add", c.mappings.add, "string", true)
                vim.validate("mappings.edit", c.mappings.edit, "string", true)
                vim.validate("mappings.older", c.mappings.older, "string", true)
                vim.validate("mappings.newer", c.mappings.newer, "string", true)
                vim.validate("mappings.arg1", c.mappings.arg1, "string", true)
                vim.validate("mappings.arg2", c.mappings.arg2, "string", true)
                vim.validate("mappings.arg3", c.mappings.arg3, "string", true)
                vim.validate("mappings.arg4", c.mappings.arg4, "string", true)
                vim.validate("mappings.arg5", c.mappings.arg5, "string", true)
        end
end

---@private
--- Apply configuration side-effects.
---
---@param config quarrel.Config Validated configuration table.
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
---@param config quarrel.Opts? Optional overrides for this call.
---
---@return quarrel.Config
H.get_config = function(config)
        return vim.tbl_deep_extend("force", H.default_config, vim.g.quarrel or {}, config or {})
end

---@private
--- Check if module is disabled.
---
---@return boolean # True if disabled globally.
H.is_disabled = function()
        return vim.g.quarrel_disable == true
end

---@private
--- Report the current arglist status.
H.notify = function()
        if not H.get_config().notify then
                return
        end

        if H.is_notify_hijacked == nil then
                local source = debug.getinfo(vim.notify, "S").source
                H.is_notify_hijacked = source ~= "@vim/_core/editor.lua"
        end

        local argv = vim.fn.argv() --[[@as string[] ]]
        local cur_idx = vim.fn.argidx() + 1
        local parts = {}
        for i, arg in ipairs(argv) do
                local f = vim.fn.fnamemodify(arg, ":.")

                if H.is_notify_hijacked then
                        f = ("[%d] = %q"):format(i, f)
                elseif i == cur_idx then
                        f = "[" .. f .. "]"
                end

                table.insert(parts, f)
        end

        local msg = table.concat(parts, "\n")
        if H.is_notify_hijacked then
                msg = "{\n  " .. table.concat(parts, ",\n  ") .. ",\n}"
        end

        vim.notify(msg, vim.log.levels.INFO, {
                title = "quarrel",
                ft = "lua",
        })
end

---@private
--- Create module autocommands.
H.create_autocommands = function()
        local group = vim.api.nvim_create_augroup("Quarrel", { clear = true })

        vim.api.nvim_create_autocmd({ "DirChangedPre", "VimLeavePre" }, {
                group = group,
                desc = "Write project-local arglist",
                callback = function(args)
                        Quarrel.write_cache()
                        if args.event ~= "VimLeavePre" then
                                return
                        end
                        -- prune any index ahead of the pointer
                        for _, history in pairs(Quarrel.cache.db.data) do
                                while #history.entries > history.index do
                                        table.remove(history.entries)
                                end
                        end
                        Quarrel.write_db()
                end,
        })

        vim.api.nvim_create_autocmd("DirChanged", {
                group = group,
                desc = "Read project-local arglist",
                callback = function()
                        Quarrel.read()
                end,
        })

        vim.api.nvim_create_autocmd({ "VimEnter" }, {
                desc = "Setup arglist on enter",
                group = group,
                callback = function()
                        H.init_arglist()
                end,
        })
end

---@private
--- Create module user commands.
H.create_usercommands = function()
        vim.api.nvim_create_user_command("Qedit", function()
                Quarrel.edit()
        end, { desc = "Edit the arglist" })

        vim.api.nvim_create_user_command("Qolder", function()
                Quarrel.older()
        end, { desc = "Go to older arglist" })

        vim.api.nvim_create_user_command("Qnewer", function()
                Quarrel.newer()
        end, { desc = "Go to newer arglist" })
end

---@private
--- Create module mappings.
---
---@param config quarrel.Config Validated configuration table.
H.create_mappings = function(config)
        local map = function(lhs, rhs, desc)
                if lhs == "" then
                        return
                end
                vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
        end

        -- define mappings
        map("<Plug>(QuarrelAdd)", function()
                Quarrel.add()
        end, "Add current file to the arglist")
        map("<Plug>(QuarrelEdit)", function()
                Quarrel.edit()
        end, "Open the arglist editor")
        map("<Plug>(QuarrelOlder)", function()
                Quarrel.older()
        end, "Go to older arglist")
        map("<Plug>(QuarrelNewer)", function()
                Quarrel.newer()
        end, "Go to newer arglist")
        map("<Plug>(QuarrelArg1)", function()
                Quarrel.goto_arg(1)
        end, "Arg file 1")
        map("<Plug>(QuarrelArg2)", function()
                Quarrel.goto_arg(2)
        end, "Arg file 2")
        map("<Plug>(QuarrelArg3)", function()
                Quarrel.goto_arg(3)
        end, "Arg file 3")
        map("<Plug>(QuarrelArg4)", function()
                Quarrel.goto_arg(4)
        end, "Arg file 4")
        map("<Plug>(QuarrelArg5)", function()
                Quarrel.goto_arg(5)
        end, "Arg file 5")

        -- apply mappings
        local m = config.mappings
        map(m.add, "<Plug>(QuarrelAdd)", "Add current file to the arglist")
        map(m.edit, "<Plug>(QuarrelEdit)", "Open the arglist editor")
        map(m.older, "<Plug>(QuarrelOlder)", "Go to older arglist")
        map(m.newer, "<Plug>(QuarrelNewer)", "Go to newer arglist")
        map(m.arg1, "<Plug>(QuarrelArg1)", "Arg file 1")
        map(m.arg2, "<Plug>(QuarrelArg2)", "Arg file 2")
        map(m.arg3, "<Plug>(QuarrelArg3)", "Arg file 3")
        map(m.arg4, "<Plug>(QuarrelArg4)", "Arg file 4")
        map(m.arg5, "<Plug>(QuarrelArg5)", "Arg file 5")
end

---@private
--- Write data to database file.
---
---@param path string File path to write to.
---@param data quarrel.Argdata Data to encode and write.
H.write_db_file = function(path, data)
        local dir = vim.fs.dirname(path)
        if vim.fn.isdirectory(dir) == 0 then
                vim.fn.mkdir(dir, "p")
        end

        -- NOTE: `vim.mpack.encode` can't serialize functions, userdata, and
        --       coroutines. it's probably not relevant to our usecase but I
        --       believe that it's better to be safe than sorry.
        local ok, packed = pcall(vim.mpack.encode, data)
        if not ok then
                return
        end

        local fp = io.open(path, "wb")
        if not fp then
                return
        end
        fp:write(packed)
        fp:close()
end

---@private
--- Read data from database file.
---
---@param path string File path to read from.
---
---@return quarrel.Argdata
H.read_db_file = function(path)
        local db = {
                _meta = {
                        version = 1,
                },
                data = {},
        }

        local stat = vim.uv.fs_stat(path)
        if not stat or stat.type ~= "file" or stat.size == 0 then
                return db
        end

        local fp = io.open(path, "rb")
        local content = fp and fp:read("*all") or ""
        if fp then
                fp:close()
        end

        local ok, decoded = pcall(vim.mpack.decode, content)
        if ok and type(decoded) == "table" and decoded.data then
                db = decoded
        end

        return db
end

---@private
--- Initialize arglist from startup arguments or database.
---
--- Filters out any arguments that evaluate to a directory.
H.init_arglist = function()
        local argf_no_dir = vim.iter(vim.v.argf):map(H.is_eligible):totable()

        if #argf_no_dir == 0 then
                Quarrel.read()
                return
        end

        local cwd = vim.uv.cwd()
        if not cwd then
                return
        end
        local history = Quarrel.cache.db.data[cwd] or { index = 0, entries = {} }

        -- n+1 rule: only append if different from the current indexed entry
        if not vim.deep_equal(argf_no_dir, history.entries[history.index]) then
                table.insert(history.entries, argf_no_dir)
                history.index = #history.entries

                local hist_level = H.get_config().hist_level
                if #history.entries > hist_level then
                        table.remove(history.entries, 1)
                        history.index = #history.entries
                end
                Quarrel.cache.db.data[cwd] = history
        end

        -- always clear the list
        vim.cmd("%argdelete")
        vim.iter(argf_no_dir):each(H.argadd)
end

---@private
--- Check if a path is eligible for the arglist.
---
---@param path string Filepath to check.
---
---@return string? # The absolute path if eligible, nil otherwise.
H.is_eligible = function(path)
        if type(path) ~= "string" or path == "" then
                return nil
        end

        -- collapse redundant separators and resolve relative paths
        local abspath = vim.fs.normalize(vim.fs.abspath(path))
        if vim.fn.isdirectory(abspath) == 1 then
                return nil
        end

        -- stylua: ignore
        local roots = vim.iter({
                vim.env.TMPDIR,
                "/tmp/",
                "/var/tmp/"
        })
                -- discard $TMPDIR if unset
                :filter(function(it) return it and it ~= "" end)
                :map(function(it) return vim.fs.normalize(vim.fs.abspath(it)) end)
                :totable()

        if
                vim.iter(roots):any(function(it)
                        return vim.startswith(abspath, it)
                end)
        then
                return nil
        end

        return abspath
end

---@private
--- Add a path to the end of the arglist with proper escaping.
---
---@param path string Absolute path to add.
H.argadd = function(path)
        vim.cmd("$argadd " .. vim.fn.fnameescape(path))
end

return Quarrel

---@toc_entry TROUBLESHOOTING
---@tag Quarrel-troubleshooting
---@text
--- If you encounter issues, please follow these steps:
---
--- Run |:checkhealth| `quarrel` to verify your environment, Nvim version, and
--- database accessibility.
---
--- Use the provided minimal reproduction script to isolate the issue from your
--- personal configuration:
--- >bash
---     just repro
--- <
--- Alternatively, run it directly with Neovim:
--- >bash
---     nvim --clean -u scripts/repro.lua
--- <
---
--- If the issue persists in the minimal environment, please report it at:
---     https://github.com/yilisharcs/quarrel.nvim/issues

---@toc_entry SIMILAR PLUGINS
---@tag Quarrel-similar-plugins
---@text
--- - [ThePrimeagen/harpoon](https://github.com/ThePrimeagen/harpoon)
--- - [nvim-mini/mini.visits](https://github.com/nvim-mini/mini.visits)

-- NOTE: this modeline automatically formats docstrings for mini.doc
-- vim: textwidth=82
