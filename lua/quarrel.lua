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

---@return table arglist Arglist database.
---@return string|nil error Any errors.
---@private
function M._get_arglist_database()
        local argtable = {}
        local file, err = io.open(vim.g.quarrel.database, "r")
        repeat
                if not file then break end
                local msgpack = file:read("*a")
                file:close()
                if not msgpack then
                        err = "Database is empty."
                        break
                end
                if #msgpack ~= 0 then argtable = vim.mpack.decode(msgpack) end
        until true
        return argtable, err
end

function M.argread()
        vim.cmd("silent! %argdelete")
        local arglist, err = M._get_arglist_database()
        if err then
                vim.notify(err, vim.log.levels.ERROR, { title = "quarrel" })
                return
        end

        local cwd = vim.uv.cwd()
        local args = arglist[cwd]
        if args == nil or #args == 0 then return end
        local argstr = table.concat(args, " ")
        vim.cmd.argadd(argstr)
end

function M.argwrite()
        local arglist, err = M._get_arglist_database()
        if err then
                vim.notify(err, vim.log.levels.ERROR, { title = "quarrel" })
                return
        end

        ---@diagnostic disable-next-line: redefined-local
        local file, err = io.open(vim.g.quarrel.database, "w")
        if not file then
                ---@diagnostic disable-next-line: param-type-mismatch
                vim.notify(err, vim.log.levels.ERROR, { title = "quarrel" })
                return
        end

        local argv = vim.fn.argv()
        if argv and #argv > 0 then
                local cwd = vim.uv.cwd()
                local data = { [cwd] = argv }
                for k, v in pairs(data) do
                        arglist[k] = v
                end
        end

        -- Clean up paths with no arglists if any shows up
        for k, v in pairs(arglist) do
                if #v == 0 then arglist[k] = nil end
        end

        local msgpack = vim.mpack.encode(arglist)
        file:write(msgpack)
        file:close()
end

function M.launch_args()
        if not vim.g.quarrel_has_argv then
                vim.g.quarrel_has_argv = true
                if #vim.v.argv > 2 and vim.env.NVIM == nil then
                        M.argwrite()
                        return
                end
        end
end

return M
