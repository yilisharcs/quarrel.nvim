local Health = {}

local start = vim.health.start
local ok = vim.health.ok
local warn = vim.health.warn
local error = vim.health.error
local info = vim.health.info

function Health.check()
        start("quarrel.nvim [status]")

        -- check version
        if vim.version.cmp(vim.version(), { 0, 12, 0 }) < 0 then
                error("Neovim 0.12.0 or later is required.")
                return
        end

        if jit then
                ok("LuaJIT runtime detected.")
        else
                error("Lua runtime lacks `goto` support.", "Install a LuaJIT-based Neovim build.")

                local src = debug.getinfo(1, "S").source
                local dir = vim.fs.dirname(src:sub(2))

                local incompat = {}
                for name, type in vim.fs.dir(dir) do
                        if type == "file" and vim.fs.ext(name) == "lua" then
                                local count = 0
                                for line in io.lines(vim.fs.joinpath(dir, name)) do
                                        if line:match("goto%s+%w+") or line:match("::%w+::") then
                                                count = count + 1
                                        end
                                end
                                if count > 0 then
                                        table.insert(
                                                incompat,
                                                ("%s (%d usages)"):format(name, count)
                                        )
                                end
                        end
                end

                if #incompat > 0 then
                        warn("Files containing `goto`:")
                        for _, f in ipairs(incompat) do
                                info("->     " .. f)
                        end
                end

                return
        end

        -- load module for final checks
        local res, Quarrel = pcall(require, "quarrel")
        if not res then
                error("Could not load 'quarrel' module.")
                return
        end

        -- check configuration
        local config_ok, err = pcall(Quarrel.__INTERNAL_H.validate_config, vim.g.quarrel)
        if not config_ok then
                error(("Invalid configuration: %s"):format(err))
        else
                ok("Configuration is valid.")
        end

        -- check enabled
        if vim.g.quarrel_disable == true then
                warn("Globally disabled (vim.g.quarrel_disable).")
        end

        -- check database
        start("quarrel.nvim [database]")

        local db_path = Quarrel.config.database
        info(("DB path: `%q`"):format(db_path))

        local db_dir = vim.fs.dirname(db_path)
        local stat = vim.uv.fs_stat(db_dir)
        if not (stat and stat.type == "directory") then
                warn(("Directory does not exist: `%q`"):format(db_dir))
                if vim.uv.fs_access(vim.fs.dirname(db_dir), "w") then
                        ok(table.concat({
                                "Parent directory is writable.",
                                "{quarrel.nvim} will create database directory on save.",
                        }, "\n"))
                else
                        error(table.concat({
                                "Parent directory is not writable.",
                                "{quarrel.nvim} won't be able to create the database.",
                        }, "\n"))
                end
        else
                ok("Directory exists.")
                if not vim.uv.fs_access(db_dir, "w") then
                        error("Directory is not writable.")
                end
        end

        if vim.uv.fs_access(db_path, "r") then
                if vim.uv.fs_access(db_path, "w") then
                        ok("DB is readable and writable.")
                else
                        error("DB exists but is not writable.")
                end

                local fp = io.open(db_path, "rb")
                local content = fp and fp:read("*all") or ""
                if fp then
                        fp:close()
                end

                -- check msgpack integrity
                if #content > 0 then
                        local m_res, _ = pcall(vim.mpack.decode, content)
                        if m_res then
                                ok("DB contains valid msgpack data.")
                        else
                                error(
                                        "DB is corrupted: invalid msgpack.",
                                        ("Delete the corrupted file: `rm %q`"):format(db_path)
                                )
                        end
                else
                        info("DB is empty.")
                end
        end

        -- check mappings
        start("quarrel.nvim [mappings]")
        local mappings = Quarrel.config.mappings
        if mappings == false then
                info("Mappings are disabled.")
                return
        end

        local keys = vim.iter(vim.tbl_keys(mappings))
                :filter(function(k)
                        return mappings[k] ~= ""
                end)
                :totable()
        table.sort(keys)

        for _, name in ipairs(keys) do
                local lhs = mappings[name]
                local map = vim.fn.maparg(lhs, "n", false, true)
                local expected_rhs = ("<Plug>(Quarrel%s%s)"):format(
                        name:sub(1, 1):upper(),
                        name:sub(2)
                )

                if vim.tbl_isempty(map) or map.rhs == expected_rhs then
                        ok(("`%s`"):format(lhs))
                        goto next_mapping
                end

                local source = "Unknown"
                if map.sid > 0 then
                        local script = vim.fn.getscriptinfo({ sid = map.sid })
                        if script and script[1] then
                                source = script[1].name
                                if map.lnum > 0 then
                                        source = ("%s:%d"):format(source, map.lnum)
                                end
                        end
                end

                local msg = ("Key `%s` is overwritten"):format(lhs)
                if map.desc and map.desc ~= "" then
                        msg = ("%s (%s)"):format(msg, map.desc)
                end

                local details = ("RHS: `%s`"):format((map.rhs ~= "" and map.rhs or "Lua function"))
                if map.buffer ~= 0 then
                        source = ("Buffer-local (%d)"):format(map.buffer)
                end
                if source ~= "Unknown" then
                        details = ("%s\nSRC: `%s`"):format(details, source)
                end

                warn(msg, details)

                ::next_mapping::
        end

        -- check dependencies
        start("quarrel.nvim [dependencies:mini.misc]")
        local has_mini_misc, mini_misc = pcall(require, "mini.misc")
        if has_mini_misc then
                ok("{mini.misc} is installed.")

                local has_auto_root, auto_root_cmds =
                        pcall(vim.api.nvim_get_autocmds, { group = "MiniMiscAutoRoot" })
                if has_auto_root and #auto_root_cmds > 0 then
                        ok("`setup_auto_root()` is active.")
                elseif type(mini_misc.setup_auto_root) == "function" then
                        local msg = "`setup_auto_root()` is inactive."
                        local fix = 'Enable with `require("mini.misc").setup_auto_root({`'
                                .. '\n`     ".git",`'
                                .. '\n`     ".jj",`'
                                .. "\n`})`"

                        if Quarrel.config.use_vcs then
                                msg = msg .. " Recommended for consistent branch isolation."
                        end
                        warn(msg, fix)
                end

                local has_restore_cursor, restore_cursor_cmds =
                        pcall(vim.api.nvim_get_autocmds, { group = "MiniMiscRestoreCursor" })
                if has_restore_cursor and #restore_cursor_cmds > 0 then
                        ok("`setup_restore_cursor()` is active.")
                elseif type(mini_misc.setup_restore_cursor) == "function" then
                        warn(
                                "`setup_restore_cursor()` is inactive.",
                                'Enable with `require("mini.misc").setup_restore_cursor()`'
                        )
                end
        else
                info("{mini.misc} (optional) is not installed.")
        end

        start("quarrel.nvim [dependencies:others]")
        if pcall(require, "yazi") then
                ok("{yazi.nvim} is installed.")
        else
                info("{yazi.nvim} (optional) is not installed.")
        end

        if pcall(require, "fzf-lua") then
                ok("{fzf-lua} is installed.")
        else
                info("{fzf-lua} (optional) is not installed.")
        end
end

return Health
