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
--- manage these multiple files. Whenever you change directories or vcs branches,
--- it'll save the arglist of the previous directory and load the next one's.
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
--- :Qedit[!]               Open a |special-buffer| with 'filetype' quarrel for the
---                         current directory's arglist. Edits, additions,
---                         removals, and shuffles are committed to the cache on
---                         save.
---                         If called as `:Qedit!`, it opens the database browser
---                         in a new tab. The entire `Quarrel.cache.db.data` table
---                         is displayed as a Lua literal. Edit freely and |:write|
---                         to validate, confirm, and save.
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
--- `vim.g.quarrel` before the plugin is loaded, and provides a global Lua table for
--- scripting. Call `Quarrel.setup()` to refresh all internal side-effects.
---
--- See |Quarrel-configuration| for `config` structure and default values.
---
--- # Tips ~
---
--- Leverage built-in Neovim features to make editing more pleasant:
---     - Edit the |:previous| or |:next| arglist files with `[a` and `a]`.
---     - |:rewind| to the first or jump to the |:last| arglist files with `[A` and `A]`.
---     - Operate on the arglist with |:argdo|.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.quarrel_disable` (globally) to `true`.

-- ################################################################################################
--
--                                       MODULE DEFINITION
--
-- ################################################################################################

local Quarrel = {}
local H = {}

local DEFAULT_DB = vim.fs.joinpath(vim.fn.stdpath("state"), "quarrel/quarrel.msgpack")

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
---@field use_vcs boolean Use version control state to manage isolated arglists.
---     Switching branches will automatically switch the active arglist stack.
---     [EXPERIMENTAL] Check out the implementation: `H.get_current_scope(cwd)`.
---
---     Supported:
---             - git
---             - jujutsu
---
---     Default: `false`
---
---@field notify boolean Whether to automatically echo the arglist on changes.
---     Default: `false`
---
---@field blacklist string[] List of directory paths to ignore. Supports absolute
---     paths or home-relative paths (e.g., `~/Projects/foo`).
---
---     Default:
--- >lua
---     {
---             vim.fs.dirname(DEFAULT_DB),
---             "/tmp",
---             "/var/tmp",
---             vim.env.TMPDIR,
---     }
--- <
---
---@field mappings (quarrel.Mappings|false) Module mappings. Use `false` to
---     disable everything, or '' (empty string) to disable one.
---
---@usage >lua
---     ---@type quarrel.Opts
---     vim.g.quarrel = {
---             database = vim.fs.joinpath(vim.env.HOME, ".quarrel.msgpack"),
---             hist_level = 10,
---             notify = true,
---             use_vcs = true,
---             blacklist = { "~/Malware" },
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
---@field edit_db string Edit the database.
---     Default: `"<leader>E"`
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
        database = DEFAULT_DB,
        hist_level = 3,
        use_vcs = false,
        notify = false,
        blacklist = {
                vim.fs.dirname(DEFAULT_DB),
                "/tmp",
                "/var/tmp",
                vim.env.TMPDIR or "",
        },
        mappings = {
                add = "<leader>a",
                edit = "<leader>e",
                edit_db = "<leader>E",
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
---     - It is not a directory.
---     - It is not located in a temporary directory (e.g., /tmp, /var/tmp).
---     - It is not an empty string.

--- Write current arglist to the in-memory cache.
---
--- Under normal operation, this is handled with |DirChangedPre| (on |:chdir|) and
--- |VimLeavePre| (on |:quit|) |autocommand|s. Call this manually to commit the active
--- arglist to the session state without touching the disk. Updates the active
--- snapshot to match the current arglist.
function Quarrel.write_cache()
        if H.should_ignore() then
                return
        end

        local cwd = vim.uv.cwd()
        if not cwd then
                return
        end

        local key = H.get_active_key(cwd)
        local argv = vim.fn.argv() --[[@as string[] ]]
        H.update_history(key, argv, "overwrite")
end

--- Write the in-memory cache to the database file.
---
--- Commits the current state of all project arglists to the msgpack database file.
--- This is handled automatically on |VimLeavePre|.
---
---@param config? quarrel.Opts @deprecated
---     Manipulate `Quarrel.config` directly instead.
function Quarrel.write_db(config)
        local db = config and config.database or Quarrel.config.database
        H.write_db_file(db, Quarrel.cache.db)
end

--- Read project-local arglist from the in-memory cache.
---
--- Under normal operation, this is handled with |DirChanged| (after |:chdir|) and
--- |VimEnter| (on startup) |autocommand|s. Call this manually to sync the active
--- arglist with the stored state for the current directory.
function Quarrel.read()
        if H.should_ignore() then
                return
        end

        local history, _ = H.get_history_context()
        local raw_list = (history and history.entries[history.index]) or {}
        local arglist = vim.iter(raw_list):map(H.is_eligible):totable()
        H.set_arglist(arglist)

        if #arglist > 0 then
                H.notify()
        end
end

--- Add a file to the arglist.
---
--- Normalizes the provided {path} to an absolute string before adding it to the
--- end of the arglist. If no {path} is provided, the result of |expand|("%:p") is
--- used. The resulting list is then deduplicated and cached.
---
---@param path string? Path to add. Supports absolute or home-relative strings. Defaults to current file.
function Quarrel.add(path)
        if H.should_ignore() then
                return
        end

        local cwd = vim.uv.cwd()
        if not cwd then
                return
        end

        local argv = vim.fn.argv() --[[@as string[] ]]
        table.insert(argv, path or vim.fn.expand("%:p"))

        local key = H.get_active_key(cwd)
        local clean = H.update_history(key, argv, "overwrite")
        if clean then
                H.set_arglist(clean)
        end

        H.notify()
end

--- Go to a specific arglist file.
---
--- Internally executes |:argument| with {idx} as the count. Like standard Vim, this
--- uses 1-based indexing. No-op if {idx} is invalid.
---
---@param idx number Arglist index.
function Quarrel.goto_arg(idx)
        if H.should_ignore() then
                return
        end
        pcall(vim.cmd.argument, { count = idx })
end

--- Navigate to the older arglist in history.
function Quarrel.older()
        if H.should_ignore() then
                return
        end

        local history, cwd = H.get_history_context()
        if not history or not cwd then
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
        if H.should_ignore() then
                return
        end

        local history, cwd = H.get_history_context()
        if not history or not cwd then
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
        if H.should_ignore() then
                return
        end

        local cwd = vim.uv.cwd()
        if not cwd then
                return
        end

        -- editor toggle
        if H.editor_buf_arg and vim.api.nvim_buf_is_valid(H.editor_buf_arg) then
                vim.api.nvim_buf_delete(H.editor_buf_arg, { force = true })
                H.editor_buf_arg = nil
                return
        end

        local buf = vim.api.nvim_create_buf(false, true)
        H.editor_buf_arg = buf
        local win = vim.api.nvim_open_win(buf, true, { split = "below" })

        vim.api.nvim_buf_set_name(buf, "quarrel://" .. cwd)
        vim.api.nvim_set_option_value("filetype", "quarrel", { buf = buf })
        vim.api.nvim_set_option_value("syntax", "gitignore", { buf = buf })
        vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
        vim.api.nvim_set_option_value("number", true, { win = win })
        vim.api.nvim_set_option_value("relativenumber", false, { win = win })
        vim.api.nvim_set_option_value("colorcolumn", "0", { win = win })
        vim.api.nvim_set_option_value("wrap", false, { win = win })

        local raw_argv = vim.fn.argv() --[[@as string[] ]]
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, raw_argv)
        vim.api.nvim_set_option_value("modified", false, { buf = buf })

        vim.api.nvim_create_autocmd("BufWriteCmd", {
                buffer = buf,
                callback = function()
                        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

                        local key = H.get_active_key(cwd)
                        local clean = H.update_history(key, lines, "overwrite")
                        if clean then
                                H.set_arglist(clean)
                        end

                        vim.api.nvim_set_option_value("modified", false, { buf = buf })
                end,
        })
end

---@private
--- Toggle the database editor.
---
--- Displays `Quarrel.cache.db.data` as a Lua table literal in a scratch buffer.
--- Edits, additions, removals, and shuffles are parsed with `load()`, validated,
--- and written to the cache.
function H.open_db_editor()
        -- editor toggle
        if H.editor_buf_db and vim.api.nvim_buf_is_valid(H.editor_buf_db) then
                vim.api.nvim_buf_delete(H.editor_buf_db, { force = true })
                H.editor_buf_db = nil
                return
        end

        local buf = vim.api.nvim_create_buf(false, true)
        H.editor_buf_db = buf
        vim.api.nvim_open_tabpage(buf, true, {})
        local win = vim.api.nvim_get_current_win()

        vim.api.nvim_buf_set_name(buf, "quarrel://[DATABASE]")
        vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })
        vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
        vim.api.nvim_set_option_value("shiftwidth", 2, { buf = buf })
        vim.api.nvim_set_option_value("tabstop", 2, { buf = buf })
        vim.api.nvim_set_option_value("softtabstop", -1, { buf = buf })
        vim.api.nvim_set_option_value("colorcolumn", "0", { win = win })
        vim.api.nvim_set_option_value("wrap", false, { win = win })

        local header = {
                "-- quarrel.nvim database browser",
                "-- Edit the data below and :wq to commit.",
                ("-- Inspected at %s"):format(os.date("%Y-%m-%d %H:%M:%S")),
                "",
        }

        local indent_str = string.rep(" ", 2)

        local dump = vim.inspect(Quarrel.cache.db.data, {
                indent = indent_str,
                process = function(item, path)
                        if path[#path] == vim.inspect["METATABLE"] then
                                return nil
                        end
                        return item
                end,
        })

        -- force vertical expansion
        dump = dump:gsub(", ", ",\n")
        dump = dump:gsub("{ ", "{\n")
        dump = dump:gsub(" }", "\n}")

        -- indentation and trailing commas
        local lines = vim.split(dump, "\n")
        local level = 0
        local formatted = {}
        for _, line in ipairs(lines) do
                line = vim.trim(line)
                if line == "" then
                        goto continue
                end

                -- dedent if line starts with a closing delimiter
                if line:find("^[%}%]]") then
                        level = math.max(0, level - 1)
                end

                -- ensure trailing comma unless line ends with an opener or separator
                -- skip the root closing brace where it is flush against the left margin
                if not line:find("[,%{ %[ %(]$") and not (level == 0 and line:find("^[%}%]]$")) then
                        line = line .. ","
                end

                -- apply indentation and collect the line
                table.insert(formatted, string.rep(indent_str, level) .. line)

                -- increment level if line ends with an opening delimiter
                if line:find("[%{%[]$") then
                        level = level + 1
                end

                ::continue::
        end

        local final_lines = vim.list_extend({}, header)
        vim.list_extend(final_lines, formatted)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, final_lines)
        vim.api.nvim_set_option_value("modified", false, { buf = buf })

        vim.api.nvim_create_autocmd("BufWriteCmd", {
                buffer = buf,
                callback = function()
                        H.editor_db_cb(buf)
                end,
        })
end

function H.editor_db_cb(buf)
        local ls = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local text = table.concat(ls, "\n")

        -- parse and check syntax
        local chunk, err = load("return " .. text)
        if not chunk then
                vim.notify("quarrel: " .. err, vim.log.levels.ERROR, { title = "quarrel" })
                return
        end

        -- execute in protected mode
        local ok, data = pcall(chunk)
        if not ok then
                vim.notify(
                        "quarrel: " .. tostring(data),
                        vim.log.levels.ERROR,
                        { title = "quarrel" }
                )
                return
        end

        -- validate against schema
        if type(data) ~= "table" then
                vim.notify(
                        "quarrel: database must be a table",
                        vim.log.levels.ERROR,
                        { title = "quarrel" }
                )
                return
        end
        for key, val in pairs(data) do
                if type(key) ~= "string" or type(val) ~= "table" then
                        vim.notify(
                                ("quarrel: invalid entry for key %s"):format(tostring(key)),
                                vim.log.levels.ERROR,
                                { title = "quarrel" }
                        )
                        return
                end

                if
                        type(val.index) ~= "number"
                        or val.index < 1
                        or val.index > Quarrel.config.hist_level
                then
                        vim.notify(
                                ("quarrel: key %s has invalid index"):format(key),
                                vim.log.levels.ERROR,
                                { title = "quarrel" }
                        )
                        return
                end

                if type(val.entries) ~= "table" or #val.entries == 0 then
                        vim.notify(
                                ("quarrel: key %s has invalid entries"):format(key),
                                vim.log.levels.ERROR,
                                { title = "quarrel" }
                        )
                        return
                end

                for i, entry in ipairs(val.entries) do
                        if type(entry) ~= "table" then
                                vim.notify(
                                        ("quarrel: key %s entries[%s] is not an array"):format(
                                                key,
                                                i
                                        ),
                                        vim.log.levels.ERROR,
                                        { title = "quarrel" }
                                )
                                return
                        end
                        for j, path in ipairs(entry) do
                                if type(path) ~= "string" then
                                        vim.notify(
                                                ("quarrel: key %s entries[%s][%s] is not a string"):format(
                                                        key,
                                                        i,
                                                        j
                                                ),
                                                vim.log.levels.ERROR,
                                                { title = "quarrel" }
                                        )
                                        return
                                end
                        end
                end
        end

        local choice = vim.fn.confirm("Overwrite database with buffer contents?", "&Yes\n&No")
        if choice ~= 1 then
                return
        end

        Quarrel.cache.db.data = data
        Quarrel.read()

        vim.api.nvim_set_option_value("modified", false, { buf = buf })
end

-- ################################################################################################
--
--                                         HELPER DATA
--
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
                        local data = H.read_db_file(Quarrel.config.database)
                        rawset(self, "db", data)
                        return data
                end
        end,
})

---@private
---@type quarrel.Config
H.DEFAULT_CONFIG = vim.deepcopy(Quarrel.config)

---@private
---@type number?
H.editor_buf_arg = nil

---@private
---@type number?
H.editor_buf_db = nil

---@private
---@type boolean?
H.is_notify_hijacked = nil

---@private
---@type string[]
H.resolved_blacklist = {}

-- ################################################################################################
--
--                                     HELPER FUNCTIONALITY
--
-- ################################################################################################

---@private
--- Setup configuration.
---
---@param config quarrel.Opts? Raw configuration table.
---
---@return quarrel.Config # Validated and merged configuration.
function H.setup_config(config)
        H.validate_config(config)

        local base = vim.deepcopy(H.DEFAULT_CONFIG)
        local user = config or {}
        local merged = vim.tbl_deep_extend("force", base, user) --[[@as quarrel.Config]]

        -- stylua: ignore
        if user.blacklist then
                -- `tbl_deep_extend` replaces nested lists entirely rather than
                -- merging them. manually concatenate defaults with user entries
                -- so the user adds to the blacklist rather than replace it.
                merged.blacklist = vim.iter({
                        base.blacklist,
                        user.blacklist
                })
                :flatten()
                :unique()
                :totable()
        end

        return merged
end

---@private
---@param config quarrel.Opts? Raw configuration table.
function H.validate_config(config)
        vim.validate("config", config, "table", true)
        local c = config or {}

        vim.validate("database", c.database, "string", true)
        vim.validate("hist_level", c.hist_level, "number", true)
        vim.validate("use_vcs", c.use_vcs, "boolean", true)
        vim.validate("notify", c.notify, "boolean", true)
        vim.validate("blacklist", c.blacklist, "table", true)
        vim.validate("mappings", c.mappings, { "table", "boolean" }, true)

        if type(c.mappings) == "table" then
                vim.validate("mappings.add", c.mappings.add, "string", true)
                vim.validate("mappings.edit", c.mappings.edit, "string", true)
                vim.validate("mappings.edit_db", c.mappings.edit_db, "string", true)
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
function H.apply_config(config)
        Quarrel.config = config
        vim.g.quarrel = config

        -- stylua: ignore
        H.resolved_blacklist = vim.iter(config.blacklist or {})
                :filter(function(it) return it and it ~= "" end)
                :map(H.resolve)
                :totable()

        H.create_autocommands()
        H.create_usercommands()
        H.create_mappings(config)
end

---@private
--- Create module autocommands.
function H.create_autocommands()
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
function H.create_usercommands()
        vim.api.nvim_create_user_command("Qedit", function(opts)
                if opts.bang then
                        H.open_db_editor()
                else
                        Quarrel.edit()
                end
        end, { bang = true, desc = "Edit the arglist or browse the database" })

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
function H.create_mappings(config)
        if config.mappings == false then
                return
        end

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
        map("<Plug>(QuarrelEditDB)", function()
                H.open_db_editor()
        end, "Open the database editor")
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
        local m = config.mappings --[[@as quarrel.Mappings]]
        map(m.add, "<Plug>(QuarrelAdd)", "Add current file to the arglist")
        map(m.edit, "<Plug>(QuarrelEdit)", "Open the arglist editor")
        map(m.edit_db, "<Plug>(QuarrelEditDB)", "Open the database editor")
        map(m.older, "<Plug>(QuarrelOlder)", "Go to older arglist")
        map(m.newer, "<Plug>(QuarrelNewer)", "Go to newer arglist")
        map(m.arg1, "<Plug>(QuarrelArg1)", "Arg file 1")
        map(m.arg2, "<Plug>(QuarrelArg2)", "Arg file 2")
        map(m.arg3, "<Plug>(QuarrelArg3)", "Arg file 3")
        map(m.arg4, "<Plug>(QuarrelArg4)", "Arg file 4")
        map(m.arg5, "<Plug>(QuarrelArg5)", "Arg file 5")
end

---@private
--- Check if a path is blacklisted.
---
---@param path string Path to check.
---
---@return boolean # True if the path or its parent is blacklisted.
function H.is_blacklisted(path)
        local abspath = H.resolve(path)
        return vim.iter(H.resolved_blacklist):any(function(item)
                return vim.startswith(abspath, item)
        end)
end

---@private
--- Check if module should ignore the current context.
---
---@param path string? Path to check. Defaults to |current-directory|.
---
---@return boolean # True if disabled or blacklisted.
function H.should_ignore(path)
        local cwd = path or vim.uv.cwd()
        if not cwd then
                return true
        end
        return H.is_disabled() or H.is_blacklisted(cwd)
end

---@private
--- Check if module is disabled.
---
---@return boolean # True if disabled globally.
function H.is_disabled()
        return vim.g.quarrel_disable == true
end

---@private
--- Report the current arglist status.
function H.notify()
        if not Quarrel.config.notify then
                return
        end

        if H.is_notify_hijacked == nil then
                local info = debug.getinfo(vim.notify, "Su")
                -- NOTE: source checks for snacks.nvim, nups checks for mini.nvim
                H.is_notify_hijacked = info.source ~= "@vim/_core/editor.lua" or info.nups > 0
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
--- Write data to database file.
---
---@param path string File path to write to.
---@param data quarrel.Argdata Data to encode and write.
function H.write_db_file(path, data)
        local dir = vim.fs.dirname(path)
        if vim.fn.isdirectory(dir) == 0 then
                vim.fn.mkdir(dir, "p")
        end

        -- NOTE: `vim.mpack.encode` can't serialize functions, userdata, and
        --       coroutines. it's probably not relevant to our usecase but I
        --       believe that it's better to be safe than sorry.
        local ok, packed = pcall(vim.mpack.encode, data)
        if not ok then
                vim.notify(
                        "quarrel: could not serialize database",
                        vim.log.levels.WARN,
                        { title = "quarrel" }
                )
                return
        end

        local tmp_path = path .. ".tmp"
        local fp = io.open(tmp_path, "wb")
        if not fp then
                vim.notify(
                        "quarrel: could not open temporary file for writing",
                        vim.log.levels.WARN,
                        { title = "quarrel" }
                )
                return
        end
        fp:write(packed)
        fp:close()

        -- replace the database file atomically; if the
        -- swap fails, the original file is preserved.
        local success, _err = vim.uv.fs_rename(tmp_path, path)
        if not success then
                os.remove(tmp_path)
        end
end

---@private
--- Read data from database file.
---
---@param path string File path to read from.
---
---@return quarrel.Argdata
function H.read_db_file(path)
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
--- Resolve a path to its canonical absolute form.
---
--- Normalizes the path by resolving relative segments and following symlinks.
---
---@param path string File or directory path.
---
---@return string # The resolved absolute path.
function H.resolve(path)
        return vim.fs.normalize(vim.uv.fs_realpath(path) or vim.fs.abspath(path))
end

---@private
--- Get the current VCS scope. [EXPERIMENTAL]
---
--- VCS identifiers (such as branches or bookmarks) define the active history
--- stack and serve as the isolation suffix for the project's database key.
--- If no context is detected, the project's base key is used as a fallback;
--- new contexts automatically inherit history from this state.
---
---@param cwd string Project directory.
---
---@return string? # The scope name, or nil if none found.
function H.get_current_scope(cwd)
        local scope
        if not Quarrel.config.use_vcs then
                goto finalize
        else
                goto jujutsu
        end

        ::jujutsu::
        -- 1. nearest ancestor bookmark: any commit descending from a bookmark
        --    inherits its context until a newer bookmark is encountered.
        -- 2. stable change ID: for anonymous work, uses the immutable change ID
        --    to associate the arglist with the current logical task.
        do
                if
                        vim.fn.executable("jj") == 0
                        or vim.fn.isdirectory(vim.fs.joinpath(cwd, ".jj")) == 0
                then
                        goto git
                end

                -- stylua: ignore
                local bookmarks_obj = vim.system({
                        "jj", "log",
                        "-r", "heads(ancestors(@) & (bookmarks() | remote_bookmarks()))",
                        "-T", 'bookmarks.join(" ")',
                        -- strip any pesky ANSI sequences
                        "--color=never", "--no-graph",
                }, { text = true, cwd = cwd }):wait()

                if bookmarks_obj.code == 0 and bookmarks_obj.stdout ~= "" then
                        local bookmarks = vim.trim(bookmarks_obj.stdout)
                        -- pick first bookmark from one or many
                        -- strip "at" marker (*) and remote suffixes (@)
                        scope = bookmarks:match("^(%S+)")
                        scope = scope:gsub("%*$", ""):gsub("@%S+$", "")
                        goto finalize
                end

                -- stylua: ignore
                local change_id_obj = vim.system({
                        "jj", "log",
                        "-r", "@",
                        "-T", "change_id.shortest(8)",
                        -- strip any pesky ANSI sequences
                        "--color=never", "--no-graph",
                }, { text = true, cwd = cwd }):wait()

                if change_id_obj.code == 0 and change_id_obj.stdout ~= "" then
                        scope = vim.trim(change_id_obj.stdout)
                end

                -- project is managed by jujutsu.
                -- do not fallback to git.
                goto finalize
        end

        ::git::
        -- 1. branch name: maps arglists to the active tracking branch.
        -- 2. short SHA: provides isolation for detached HEAD states.
        do
                if vim.fn.executable("git") == 0 then
                        goto finalize
                end

                -- stylua: ignore
                local branch_obj = vim.system({
                        -- strip any pesky ANSI color sequences
                        -- (git is shy, but you never know...)
                        "git", "-c", "color.ui=never",
                        "branch", "--show-current",
                }, { text = true, cwd = cwd }):wait()

                if branch_obj.code == 0 and branch_obj.stdout ~= "" then
                        local branch = vim.trim(branch_obj.stdout)
                        if branch ~= "" then
                                scope = branch
                                goto finalize
                        end
                end

                -- stylua: ignore
                local sha_obj = vim.system({
                        -- strip any pesky ANSI color sequences
                        -- (git is shy, but you never know...)
                        "git", "-c", "color.ui=never",
                        "rev-parse", "--short", "HEAD",
                }, { text = true, cwd = cwd }):wait()

                if sha_obj.code == 0 and sha_obj.stdout ~= "" then
                        local sha = vim.trim(sha_obj.stdout)
                        if sha ~= "" then
                                scope = sha
                        end
                end

                -- project is managed by git.
                -- do not fallback to ... what?
                goto finalize
        end

        ::finalize::

        return (scope and scope ~= "") and scope or nil
end

---@private
--- Get the active database key for the current directory.
---
---@param cwd string Directory path.
---
---@return string # The resolved key (plain cwd or vcs composite).
function H.get_active_key(cwd)
        local real_cwd = H.resolve(cwd)
        local scope = H.get_current_scope(real_cwd)
        return scope and (real_cwd .. "\0" .. scope) or real_cwd
end

---@private
--- Resolve the history, active key, and directory for the current project.
---
---@return quarrel.History?, string? # history, cwd.
function H.get_history_context()
        local cwd = vim.uv.cwd()
        if not cwd then
                return nil, nil
        end

        local key = H.get_active_key(cwd)
        local history = Quarrel.cache.db.data[key]

        -- if on a new branch, inherit from base cwd
        local base_cwd = not history and key:match("^(.-)%z")
        if base_cwd then
                history = Quarrel.cache.db.data[base_cwd]
        end

        return history, cwd
end

---@private
--- Synchronize the arglist with a list of files.
---
---@param files string[] List of absolute paths.
function H.set_arglist(files)
        -- always clear the list
        vim.cmd("%argdelete")

        vim.iter(files):each(H.argadd)
end

---@private
--- Initialize arglist from startup arguments or database.
---
--- Filters out any arguments that evaluate to a directory.
function H.init_arglist()
        if H.should_ignore() then
                return
        end

        local argf_no_dir = vim.iter(vim.v.argf):map(H.is_eligible):totable()

        if #argf_no_dir == 0 then
                Quarrel.read()
                return
        end

        local cwd = vim.uv.cwd()
        if not cwd then
                return
        end

        local key = H.get_active_key(cwd)
        local clean = H.update_history(key, argf_no_dir, "append")
        if clean then
                H.set_arglist(clean)
        end
end

---@private
--- Check if a path is eligible for the arglist.
---
---@param path string Filepath to check.
---
---@return string? # The absolute path if eligible, nil otherwise.
function H.is_eligible(path)
        if type(path) ~= "string" or path == "" then
                return nil
        end

        local abspath = H.resolve(path)
        if vim.fn.isdirectory(abspath) == 1 then
                return nil
        end

        if H.is_blacklisted(abspath) then
                return nil
        end

        return abspath
end

---@private
--- Add a path to the end of the arglist with proper escaping.
---
---@param path string Path to add.
function H.argadd(path)
        vim.cmd("$argadd " .. vim.fn.fnameescape(path))
end

---@private
--- Update the history for a project.
---
---@param key string Database key (directory path).
---@param files string[] List of files to store.
---@param mode "overwrite"|"append" Update mode.
---
---@return string[]? # The normalized list of files, or nil if no update occurred.
function H.update_history(key, files, mode)
        local history = Quarrel.cache.db.data[key] or { index = 0, entries = {} }
        -- stylua: ignore
        local normalized = vim.iter(files)
                :map(H.is_eligible)
                -- ":argdedup" happens here
                :unique()
                :totable()

        -- avoid creating empty histories for empty projects
        if #normalized == 0 and #history.entries == 0 then
                return nil
        end

        -- change detection: avoid redundant snapshots
        if history.index > 0 and vim.deep_equal(normalized, history.entries[history.index]) then
                return normalized
        end

        if mode == "overwrite" and history.index > 0 then
                -- session update: replace current snapshot
                history.entries[history.index] = normalized
        elseif mode == "append" or (mode == "overwrite" and history.index == 0) then
                -- checkpoint update: create new snapshot
                table.insert(history.entries, normalized)
                history.index = #history.entries

                -- enforce history limit
                local hist_level = Quarrel.config.hist_level
                if #history.entries > hist_level then
                        table.remove(history.entries, 1)
                        history.index = #history.entries
                end
        else
                error(("Invalid update mode %q (expected 'overwrite' or 'append')"):format(mode))
        end

        Quarrel.cache.db.data[key] = history

        -- if it's a composite key, update base_cwd for backwards compatibility
        local base_cwd = key:match("^(.-)%z")
        if base_cwd then
                H.update_history(base_cwd, normalized, mode)
        end

        return normalized
end

-- expose internal access for Busted and :checkhealth
setmetatable(Quarrel, {
        __index = function(_, key)
                if key == "__INTERNAL_H" then
                        return H
                end
        end,
        -- block set and get metatable
        __metatable = "INTERNAL",
})

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
--- If the issue persists in the minimal environment, please report it at:
---     https://codeberg.org/yilisharcs/quarrel.nvim/issues

---@toc_entry SIMILAR PLUGINS
---@tag Quarrel-similar-plugins
---@text
---     - [ThePrimeagen/harpoon](https://github.com/ThePrimeagen/harpoon)
---     - [nvim-mini/mini.visits](https://github.com/nvim-mini/mini.visits)

-- NOTE: this modeline automatically formats docstrings for mini.doc
-- vim: textwidth=82
