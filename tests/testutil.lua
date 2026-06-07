local Quarrel = require("quarrel")
local M = {}

M.root = vim.fs.normalize(assert(vim.uv.cwd()))
M.artifacts = vim.fs.joinpath(M.root, "tests/artifacts")
M.database = vim.fs.joinpath(M.artifacts, "quarrel.msgpack")

--- Reset the plugin state to a clean baseline.
---
---@param config quarrel.Opts? Optional configuration overrides.
function M.clear(config)
        -- reload plugin
        Quarrel.setup(vim.tbl_deep_extend("force", {
                database = M.database,
        }, config or {}))

        -- reset the in-memory database
        Quarrel.cache.db = {
                _meta = { version = 1 },
                data = {},
        }

        -- clear arglist
        vim.cmd("%argdelete")
end

--- Bootstrap the test environment.
---
--- Injects helper functions and registers hooks.
function M.setup()
        local env = getfenv(2)
        local original_cwd = assert(vim.uv.cwd())

        -- inject helpers into the caller's scope
        env.clear = M.clear

        if env.before_each then
                env.before_each(function()
                        M.clear()
                end)
        end

        if env.after_each then
                env.after_each(function()
                        vim.uv.chdir(original_cwd)
                end)
        end
end

--- Create a temporary directory inside artifacts.
---
---@return string # Path to the created directory.
function M.create_temp_dir()
        local hex_id = ("%x"):format(math.random(0x100000, 0xffffff))
        local path = vim.fs.joinpath(M.artifacts, hex_id)
        vim.fn.mkdir(path, "p")
        return path
end

return M
