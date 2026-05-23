package.path = "./vendor/mini.doc/lua/?.lua;" .. package.path

local minidoc = require("mini.doc")
minidoc.setup()

-- documentation manifest. `entrypoint` is explicitly placed at the first index
-- of the input array passed to `minidoc.generate()` so it can be accessible as
-- doc[1] in its many hooks.
local manifest = {
        entrypoint = "lua/quarrel/init.lua",
        metadata = {},
}
setmetatable(manifest, {
        __call = function(self) return { self.entrypoint, unpack(self.metadata) } end,
})

local H = {}

-- indentation levels
H.s4 = string.rep(" ", 4)
H.s8 = string.rep(" ", 8)

--- Check if any line in a section matches a literal pattern.
---
--- This function iterates through the numeric indices of a section object. It
--- returns true on the first match or nil if no match is found.
---@param section table Documentation section object.
---@param pattern string Literal string to find.
---
---@return boolean? # True if found, nil otherwise.
H.has_pattern = function(section, pattern)
        for _, line in ipairs(section) do
                if type(line) == "string" and line:find(pattern, 1, true) then return true end
        end
end

--- Find a documentation block by its class name.
H.find_block_by_class = function(doc, class_name)
        local file = doc[1]
        for _, block in ipairs(file) do
                local is_match = block:has_descendant(
                        function(s)
                                return type(s) == "table"
                                        and s.info
                                        and s.info.id == "@class"
                                        and H.has_pattern(s, class_name)
                        end
                )
                if is_match then return block end
        end
end

--- Recursively synthesize a Lua table from field definitions.
H.synthesize_lua_table = function(doc, fields, indent_level)
        local lines = {}
        local indent = string.rep(" ", indent_level)

        for _, f in ipairs(fields) do
                table.insert(lines, indent .. "-- " .. f.desc)

                if f.type:match("^quarrel%.") then
                        local sub_block = H.find_block_by_class(doc, f.type)
                        if sub_block then
                                local sub_fields = H.parse_fields(sub_block)
                                table.insert(lines, indent .. f.name .. " = {")
                                local sub_lines =
                                        H.synthesize_lua_table(doc, sub_fields, indent_level + 4)
                                vim.list_extend(lines, sub_lines)
                                table.insert(lines, indent .. "},")
                        else
                                table.insert(lines, indent .. f.name .. " = {},")
                        end
                else
                        table.insert(
                                lines,
                                indent .. f.name .. " = " .. (f.default or "nil") .. ","
                        )
                end
        end

        return lines
end

--- Parse fields from a documentation block.
H.parse_fields = function(block)
        local fields = {}
        for _, s in ipairs(block) do
                local id = (s.info and type(s.info.id) == "string") and s.info.id or ""
                if not id:match("field") then goto next_field end

                local lines = {}
                for _, l in ipairs(s) do
                        -- strip structural headers injected by mini.doc
                        if not l:match("Fields%s*.*~") then table.insert(lines, l) end
                end

                local full_text = table.concat(lines, " "):gsub("%s+", " ")
                full_text = vim.trim(full_text)

                -- handle mini.doc transformations: {name} -> name, `(type)` -> type
                full_text = full_text:gsub("^{(%S-)}", "%1")
                full_text = full_text:gsub("`%(?(%S-)%)?` ", "%1 ")

                -- match: name type description...
                local name, type_str, rest = full_text:match("^(%S+)%s+(%S+)%s*(.*)$")
                if name then
                        local desc = rest:match("(.-)%s*Default:") or rest
                        local default = rest:match("Default:%s*(.*)$")
                        if default then
                                -- strip backticks from default value
                                default = default:gsub("^`", ""):gsub("`$", "")
                        end
                        table.insert(fields, {
                                name = name,
                                type = type_str,
                                desc = vim.trim(desc),
                                default = default,
                        })
                end

                ::next_field::
        end
        return fields
end

--- Collect specific sections from a block into an accumulator table.
---
---@param block table Documentation block object.
---@param options table Filtering and transformation options.
---@param acc_tbl table Accumulator table for the collected sections.
H.collect_sections = function(block, options, acc_tbl)
        for _, s in ipairs(block) do
                local id = s.info and s.info.id
                if options.id_filter and not options.id_filter(id) then goto next_section end

                -- intra-section line filtering
                local content_block = {}
                for _, line in ipairs(s) do
                        local is_invalid = type(line) ~= "string"
                                or line:match("^%s*%-+%s*$")
                                or line:find("Fields ~", 1, true)

                        if is_invalid then goto next_line end
                        table.insert(content_block, line)

                        ::next_line::
                end

                while #content_block > 0 and content_block[#content_block] == "" do
                        table.remove(content_block)
                end

                -- don't accumulate empty section objects in the doctree. you never know...
                if #content_block > 0 then
                        local new_s = { type = "section", info = vim.deepcopy(s.info) }

                        for idx, line in ipairs(content_block) do
                                new_s[idx] = line
                        end

                        -- override section ID for class definitions to suppress the automated
                        -- horizontal line injection, while preserving the actual text content
                        if new_s.info.id == "@class" then new_s.info.id = "@text" end

                        table.insert(acc_tbl, new_s)
                end

                ::next_section::
        end
end

--- shared logic for merging config and mappings
H.prepare_doc_tree = function(doc, is_readme)
        local file = doc[1]
        local blocks = { config = nil, mappings = nil, var = nil }
        local idxs = { config = nil, mappings = nil, var = nil }

        for i, block in ipairs(file) do
                if
                        block:has_descendant(
                                function(s)
                                        return type(s) == "table"
                                                and s.info
                                                and s.info.id == "@tag"
                                                and H.has_pattern(s, "Quarrel-configuration")
                                end
                        )
                then
                        blocks.config, idxs.config = block, i
                elseif
                        block:has_descendant(
                                function(s)
                                        return type(s) == "table"
                                                and s.info
                                                and s.info.id == "@class"
                                                and H.has_pattern(s, "quarrel.Mappings")
                                end
                        )
                then
                        blocks.mappings, idxs.mappings = block, i
                elseif
                        block:has_descendant(
                                function(s)
                                        return type(s) == "table"
                                                and s.info
                                                and s.info.id == "@tag"
                                                and H.has_pattern(s, "Quarrel.config")
                                end
                        )
                then
                        blocks.var, idxs.var = block, i
                end
        end

        if is_readme and blocks.config then
                local cfg_fields = H.parse_fields(blocks.config)

                local lines = {
                        "---@type quarrel.Opts",
                        "vim.g.quarrel = {",
                }

                -- reassemble configuration documentation from ordered field objects
                local synthesized = H.synthesize_lua_table(doc, cfg_fields, 8)
                vim.list_extend(lines, synthesized)
                table.insert(lines, "}")

                local config_block = blocks.config
                -- wipe existing sections
                for j = 1, #config_block do
                        config_block[j] = nil
                end

                config_block[1] = {
                        type = "section",
                        info = { id = "@text", line_begin = -1, line_end = -1 },
                        [1] = "## CONFIGURATION",
                        [2] = "",
                        parent = config_block,
                        parent_index = 1,
                }

                local code_section = {
                        type = "section",
                        info = { id = "@text", line_begin = -1, line_end = -1 },
                        [1] = ">lua",
                        parent = config_block,
                        parent_index = 2,
                }
                for _, l in ipairs(lines) do
                        table.insert(code_section, l)
                end
                table.insert(code_section, "<")
                config_block[2] = code_section
                return
        end

        if blocks.config and blocks.mappings and blocks.var then
                local merged_sections = {
                        {
                                type = "section",
                                info = { id = "@text" },
                                [1] = string.rep("-", 78),
                        },
                }

                local blank = {
                        type = "section",
                        info = { id = "@text" },
                        [1] = "",
                }

                -- header tags
                H.collect_sections(blocks.config, {
                        id_filter = function(id) return id == "@tag" end,
                }, merged_sections)
                H.collect_sections(blocks.var, {
                        id_filter = function(id) return id == "@tag" end,
                }, merged_sections)

                -- signature and config class lead
                H.collect_sections(blocks.var, {
                        id_filter = function(id) return id == "@signature" end,
                }, merged_sections)
                H.collect_sections(blocks.config, {
                        id_filter = function(id) return id == "@class" end,
                }, merged_sections)

                table.insert(merged_sections, blank)
                table.insert(merged_sections, {
                        type = "section",
                        info = { id = "@text" },
                        [1] = "Fields ~",
                })

                -- base config fields
                local config_fields = {}
                H.collect_sections(blocks.config, {
                        id_filter = function(id) return id == "@field" end,
                }, config_fields)

                for _, field in ipairs(config_fields) do
                        table.insert(merged_sections, field)
                        if H.has_pattern(field, "{mappings}") then
                                -- inline the mappings fields
                                table.insert(merged_sections, blank)
                                table.insert(merged_sections, {
                                        type = "section",
                                        info = { id = "@text" },
                                        [1] = "Fields {quarrel.Mappings} ~",
                                })
                                local m_fields = {}
                                H.collect_sections(blocks.mappings, {
                                        id_filter = function(id) return id == "@field" end,
                                }, m_fields)

                                for _, mf in ipairs(m_fields) do
                                        table.insert(merged_sections, mf)

                                        -- NOTE: only add a blank line if the field has a multi-line
                                        --       description. why? argN was flattened on purpose.
                                        if #mf > 1 then table.insert(merged_sections, blank) end
                                end
                        else
                                table.insert(merged_sections, blank)
                        end
                end

                -- footer: config usage and removal of the @type tag
                table.insert(merged_sections, blank)
                H.collect_sections(blocks.config, {
                        id_filter = function(id) return id == "@usage" end,
                }, merged_sections)

                -- overwrite entries and trim if the new content is shorter
                for i = 1, #merged_sections do
                        blocks.config[i] = merged_sections[i]
                end
                for i = #merged_sections + 1, #blocks.config do
                        blocks.config[i] = nil
                end

                -- get rid of duplicates
                local duplicates = { idxs.mappings, idxs.var }

                -- find and remove the block for vim.g.quarrel generated
                -- from the @type annotation in the usage block
                for i, block in ipairs(file) do
                        if
                                block:has_descendant(
                                        function(s)
                                                return type(s) == "table"
                                                        and s.info
                                                        and s.info.id == "@tag"
                                                        and H.has_pattern(s, "vim.g.quarrel")
                                        end
                                )
                        then
                                table.insert(duplicates, i)
                        end
                end

                table.sort(duplicates, function(a, b) return a > b end)
                for _, idx in ipairs(duplicates) do
                        file:remove(idx)
                end
        end
end

local doc_hooks = vim.deepcopy(minidoc.config.hooks)
doc_hooks.doc = function(doc)
        local file = doc[1]
        local blocks = { config = nil, mappings = nil, var = nil }
        local idxs = { config = nil, mappings = nil, var = nil }

        for i, block in ipairs(file) do
                if
                        block:has_descendant(
                                function(s)
                                        return type(s) == "table"
                                                and s.info
                                                and s.info.id == "@tag"
                                                and H.has_pattern(s, "Quarrel-configuration")
                                end
                        )
                then
                        blocks.config, idxs.config = block, i
                elseif
                        block:has_descendant(
                                function(s)
                                        return type(s) == "table"
                                                and s.info
                                                and s.info.id == "@class"
                                                and H.has_pattern(s, "quarrel.Mappings")
                                end
                        )
                then
                        blocks.mappings, idxs.mappings = block, i
                elseif
                        block:has_descendant(
                                function(s)
                                        return type(s) == "table"
                                                and s.info
                                                and s.info.id == "@tag"
                                                and H.has_pattern(s, "Quarrel.config")
                                end
                        )
                then
                        blocks.var, idxs.var = block, i
                end
        end

        if blocks.config and blocks.mappings and blocks.var then
                local merged_sections = {
                        {
                                type = "section",
                                info = { id = "@text" },
                                [1] = string.rep("-", 78),
                        },
                }

                local blank = {
                        type = "section",
                        info = { id = "@text" },
                        [1] = "",
                }

                -- header tags
                H.collect_sections(blocks.config, {
                        id_filter = function(id) return id == "@tag" end,
                }, merged_sections)
                H.collect_sections(blocks.var, {
                        id_filter = function(id) return id == "@tag" end,
                }, merged_sections)

                -- signature and config class lead
                H.collect_sections(blocks.var, {
                        id_filter = function(id) return id == "@signature" end,
                }, merged_sections)
                H.collect_sections(blocks.config, {
                        id_filter = function(id) return id == "@class" end,
                }, merged_sections)

                table.insert(merged_sections, blank)
                table.insert(merged_sections, {
                        type = "section",
                        info = { id = "@text" },
                        [1] = "Fields ~",
                })

                -- base config fields
                local config_fields = {}
                H.collect_sections(blocks.config, {
                        id_filter = function(id) return id == "@field" end,
                }, config_fields)

                for _, field in ipairs(config_fields) do
                        table.insert(merged_sections, field)
                        if H.has_pattern(field, "{mappings}") then
                                -- inline the mappings fields
                                table.insert(merged_sections, blank)
                                table.insert(merged_sections, {
                                        type = "section",
                                        info = { id = "@text" },
                                        [1] = "Fields {quarrel.Mappings} ~",
                                })
                                local m_fields = {}
                                H.collect_sections(blocks.mappings, {
                                        id_filter = function(id) return id == "@field" end,
                                }, m_fields)

                                for _, mf in ipairs(m_fields) do
                                        table.insert(merged_sections, mf)

                                        -- NOTE: only add a blank line if the field has a multi-line
                                        --       description. why? argN was flattened on purpose.
                                        if #mf > 1 then table.insert(merged_sections, blank) end
                                end
                        else
                                table.insert(merged_sections, blank)
                        end
                end

                -- footer: config usage and removal of the @type tag
                table.insert(merged_sections, blank)
                H.collect_sections(blocks.config, {
                        id_filter = function(id) return id == "@usage" end,
                }, merged_sections)

                -- overwrite entries and trim if the new content is shorter
                for i = 1, #merged_sections do
                        blocks.config[i] = merged_sections[i]
                end
                for i = #merged_sections + 1, #blocks.config do
                        blocks.config[i] = nil
                end

                -- get rid of duplicates
                local duplicates = { idxs.mappings, idxs.var }

                -- find and remove the block for vim.g.quarrel generated
                -- from the @type annotation in the usage block
                for i, block in ipairs(file) do
                        if
                                block:has_descendant(
                                        function(s)
                                                return type(s) == "table"
                                                        and s.info
                                                        and s.info.id == "@tag"
                                                        and H.has_pattern(s, "vim.g.quarrel")
                                        end
                                )
                        then
                                table.insert(duplicates, i)
                        end
                end

                table.sort(duplicates, function(a, b) return a > b end)
                for _, idx in ipairs(duplicates) do
                        file:remove(idx)
                end
        end

        minidoc.default_hooks.doc(doc)
end

minidoc.generate(manifest(), "doc/quarrel.nvim.txt", {
        hooks = doc_hooks,
})
