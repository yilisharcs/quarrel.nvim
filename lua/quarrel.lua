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

return M
