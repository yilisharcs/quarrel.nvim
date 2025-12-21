--- *quarrel.nvim.txt*                   Automagically manage project-local arglists
---
--- Apache License 2.0 Copyright (c) 2025 yilisharcs

---                               Table of Contents
---
---@toc

---@toc_entry INTRODUCTION
---@tag Quarrel-intro
---@text
--- *quarrel.nvim* intends to fix a persistent issue in file navigation: alternate
--- buffers can't cope with multiple files and global marks don't remember cursor
--- position. This plugin leverages the built-in arglist to automatically manage
--- these multiple files. Whenever you change directories, it'll save the arglist
--- of the previous directory and load the next one's.

local M = {}

local function get_db()
        local db = vim.g.quarrel.database
        if vim.fn.filereadable(db) == 0 then return {} end

        local file = io.open(db, "r")
        if not file then return {} end
        local content = file:read("*a")
        file:close()

        if #content == 0 then return {} end

        local ok, data = pcall(vim.mpack.decode, content)
        return ok and data or {}
end

local function save_db(data)
        local db = vim.g.quarrel.database
        local tmp = db .. ".tmp"
        local file = io.open(tmp, "wb")
        if not file then return end

        local encoded = vim.mpack.encode(data)
        file:write(encoded)
        file:close()

        -- Atomic!
        os.rename(tmp, db)
end

function M.load()
        local db = get_db()
        local cwd = vim.fn.getcwd()
        local arglist = db[cwd]

        vim.cmd("silent! %argdelete")

        if arglist and #arglist > 0 then
                local str = {}
                for _, arg in ipairs(arglist) do
                        table.insert(str, vim.fn.fnameescape(arg))
                end
                vim.cmd.argadd(table.concat(str, " "))
        end
end

function M.save()
        local db = get_db()
        local cwd = vim.fn.getcwd()
        local arglist = vim.fn.argv()

        if #arglist > 0 then
                db[cwd] = arglist
        else
                db[cwd] = nil
        end

        save_db(db)
end

function M.on_enter()
        if #vim.fn.argv() > 0 then
                M.save()
        else
                M.load()
        end
end

function M.edit()
        local bufname = "quarrel://" .. vim.fn.getcwd()
        local existing = vim.fn.bufnr(bufname)
        if vim.api.nvim_buf_is_valid(existing) then
                local wins = vim.fn.win_findbuf(existing)
                if #wins > 0 then
                        vim.api.nvim_set_current_win(wins[1])
                        return
                end
                vim.api.nvim_buf_delete(existing, { force = true })
        end

        local buf = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_name(buf, bufname)
        vim.api.nvim_set_option_value("filetype", "gitignore", { buf = buf }) -- highlighting
        vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

        ---@diagnostic disable-next-line: param-type-mismatch
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.argv())
        vim.api.nvim_set_option_value("modified", false, { buf = buf })

        vim.api.nvim_create_autocmd("BufWriteCmd", {
                buffer = buf,
                callback = function()
                        -- stylua: ignore
                        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

                        local args = {}
                        for _, line in ipairs(lines) do
                                local trim = vim.trim(line)
                                if trim ~= "" then table.insert(args, trim) end
                        end

                        vim.cmd("silent! %argdelete")
                        local str = {}
                        for _, arg in ipairs(args) do
                                table.insert(str, vim.fn.fnameescape(arg))
                        end
                        vim.cmd.argadd(table.concat(str, " "))

                        M.save()

                        -- stylua: ignore start
                        vim.api.nvim_set_option_value("modified", false, { buf = buf })
                        -- stylua: ignore end
                end,
        })

        vim.cmd.new()
        vim.api.nvim_set_current_buf(buf)

        local win = vim.api.nvim_get_current_win()
        vim.api.nvim_set_option_value("number", true, { win = win })
        vim.api.nvim_set_option_value("relativenumber", false, { win = win })
end

return M
