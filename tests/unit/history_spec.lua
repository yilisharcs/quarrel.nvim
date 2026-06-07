local Quarrel = require("quarrel")
local H = Quarrel.__INTERNAL_H
local t = require("tests.testutil")

describe("history management", function()
        t.setup()
        local temp_root = t.create_temp_dir()
        local test_cwd = vim.fs.joinpath(temp_root, "project")
        vim.fn.mkdir(test_cwd, "p")

        local original_is_eligible = H.is_eligible
        local original_get_current_scope = H.get_current_scope

        before_each(function()
                vim.uv.chdir(test_cwd)

                -- mock `is_eligible`: bypass real path-filtering
                -- and return only absolute paths
                H.is_eligible = function(path)
                        if path:sub(1, 1) == "/" then
                                return path
                        else
                                return "/test/" .. path
                        end
                end
        end)

        after_each(function()
                H.is_eligible = original_is_eligible
                H.get_current_scope = original_get_current_scope
        end)

        describe("update_history", function()
                it("correctly appends new snapshots", function()
                        H.update_history(test_cwd, { "file1" }, "append")
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.same({ "/test/file1" }, history.entries[1])
                        assert.are.equal(1, history.index)

                        H.update_history(test_cwd, { "file2" }, "append")
                        assert.are.same({ "/test/file2" }, history.entries[2])
                        assert.are.equal(2, history.index)
                end)

                it("correctly overwrites the current snapshot", function()
                        H.update_history(test_cwd, { "file1" }, "append")
                        H.update_history(test_cwd, { "file1_updated" }, "overwrite")

                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.equal(1, #history.entries)
                        assert.are.same({ "/test/file1_updated" }, history.entries[1])
                        assert.are.equal(1, history.index)
                end)

                it("falls back to append if overwrite is called on empty history", function()
                        H.update_history(test_cwd, { "file1" }, "overwrite")
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.equal(1, history.index)
                        assert.are.same({ "/test/file1" }, history.entries[1])
                end)

                it("deduplicates files automatically", function()
                        H.update_history(test_cwd, { "file1", "file1", "file2" }, "append")
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.same({ "/test/file1", "/test/file2" }, history.entries[1])
                end)

                it("respects hist_level", function()
                        clear({ hist_level = 2 })

                        -- should delete this one
                        H.update_history(test_cwd, { "foo", "bar" }, "append")
                        H.update_history(test_cwd, { "span", "eggs" }, "append")
                        H.update_history(test_cwd, { "hello", "world" }, "append")

                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.equal(2, #history.entries)
                        assert.are.same({ "/test/span", "/test/eggs" }, history.entries[1])
                        assert.are.same({ "/test/hello", "/test/world" }, history.entries[2])
                        assert.are.equal(2, history.index)
                end)

                it("avoids redundant snapshots via `vim.deep_equal` check", function()
                        H.update_history(test_cwd, { "file1" }, "append")
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.equal(1, #history.entries)

                        H.update_history(test_cwd, { "file1" }, "append")
                        assert.are.equal(1, #history.entries)
                end)
        end)

        describe("navigation (:Qolder/:Qnewer)", function()
                before_each(function()
                        -- setup some history
                        H.update_history(test_cwd, { "foo", "bar" }, "append")
                        H.update_history(test_cwd, { "span", "eggs" }, "append")
                        H.update_history(test_cwd, { "hello", "world" }, "append")
                        -- we are at index 3
                end)

                it("navigates to older snapshots", function()
                        Quarrel.older()
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.equal(2, history.index)

                        Quarrel.older()
                        assert.are.equal(1, history.index)
                end)

                it("respects boundary for older snapshots", function()
                        Quarrel.older()
                        Quarrel.older() -- index is 1
                        Quarrel.older()
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.equal(1, history.index)
                end)

                it("navigates to newer snapshots", function()
                        Quarrel.older()
                        Quarrel.older() -- index is 1
                        Quarrel.newer()
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.equal(2, history.index)
                end)

                it("respects boundary for newer snapshots", function()
                        Quarrel.newer() -- already at 3
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are.equal(3, history.index)
                end)

                it("navigates vcs-scoped history correctly", function()
                        clear({ use_vcs = true })

                        -- mock scope resolution
                        H.get_current_scope = function()
                                return "feat-x"
                        end

                        local branch_key = test_cwd .. "\0" .. "feat-x"

                        -- setup some history
                        H.update_history(branch_key, { "branch-file1", "foo" }, "append")
                        H.update_history(branch_key, { "branch-file2", "bar" }, "append")

                        Quarrel.older()
                        local branch_history = Quarrel.cache.db.data[branch_key]
                        -- verify navigation acted on the scoped key, not the base cwd
                        assert.are.equal(1, branch_history.index)
                end)
        end)
end)
