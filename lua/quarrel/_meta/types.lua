---@meta _
--- Definition file for LuaLS type information.

error("Cannot require a meta file")

---@class (partial) quarrel.Opts: quarrel.Config
---@field mappings? quarrel.MappingsOpts|false

---@class (partial) quarrel.MappingsOpts: quarrel.Mappings

---@class quarrel.History
---@field index number
---@field entries string[][]

---@class quarrel.Database
---@field _meta { version: number }
---@field data table<string, quarrel.History>

---@alias quarrel.Argdata quarrel.Database

---@type quarrel.Opts?
vim.g.quarrel = vim.g.quarrel --[[@as any]]
