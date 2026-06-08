local Quarrel = require("quarrel")
local H = Quarrel.__INTERNAL_H
local t = require("tests.testutil")

describe("history management", function()
        t.setup()
        local temp_root = t.create_temp_dir()
        local test_cwd = vim.fs.joinpath(temp_root, "project")
        vim.fn.mkdir(test_cwd, "p")

        local eligible_stub, scope_stub

        before_each(function()
                vim.uv.chdir(test_cwd)

                -- bypass real path-filtering and
                -- return only absolute paths
                eligible_stub = stub(H, "is_eligible", function(path)
                        if path:sub(1, 1) == "/" then
                                return path
                        else
                                return "/test/" .. path
                        end
                end)
        end)

        after_each(function()
                eligible_stub:revert()
                if scope_stub then
                        scope_stub:revert()
                        scope_stub = nil
                end
        end)

        describe("update_history", function()
                it("correctly appends new snapshots", function()
                        H.update_history(test_cwd, { "file1" }, "append")
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_same({ "/test/file1" }, history.entries[1])
                        assert.are_equal(1, history.index)

                        H.update_history(test_cwd, { "file2" }, "append")
                        assert.are_same({ "/test/file2" }, history.entries[2])
                        assert.are_equal(2, history.index)
                end)

                it("correctly overwrites the current snapshot", function()
                        H.update_history(test_cwd, { "file1" }, "append")
                        H.update_history(test_cwd, { "file1_updated" }, "overwrite")

                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_equal(1, #history.entries)
                        assert.are_same({ "/test/file1_updated" }, history.entries[1])
                        assert.are_equal(1, history.index)
                end)

                it("falls back to append if overwrite is called on empty history", function()
                        H.update_history(test_cwd, { "file1" }, "overwrite")
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_equal(1, history.index)
                        assert.are_same({ "/test/file1" }, history.entries[1])
                end)

                it("deduplicates files automatically", function()
                        H.update_history(test_cwd, { "file1", "file1", "file2" }, "append")
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_same({ "/test/file1", "/test/file2" }, history.entries[1])
                end)

                it("respects hist_level", function()
                        clear({ hist_level = 2 })

                        -- should delete this one
                        H.update_history(test_cwd, { "foo", "bar" }, "append")
                        H.update_history(test_cwd, { "span", "eggs" }, "append")
                        H.update_history(test_cwd, { "hello", "world" }, "append")

                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_equal(2, #history.entries)
                        assert.are_same({ "/test/span", "/test/eggs" }, history.entries[1])
                        assert.are_same({ "/test/hello", "/test/world" }, history.entries[2])
                        assert.are_equal(2, history.index)
                end)

                it("avoids redundant snapshots via `vim.deep_equal` check", function()
                        H.update_history(test_cwd, { "file1" }, "append")
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_equal(1, #history.entries)

                        H.update_history(test_cwd, { "file1" }, "append")
                        assert.are_equal(1, #history.entries)
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
                        assert.are_equal(2, history.index)

                        Quarrel.older()
                        assert.are_equal(1, history.index)
                end)

                it("respects boundary for older snapshots", function()
                        Quarrel.older()
                        Quarrel.older() -- index is 1
                        Quarrel.older()
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_equal(1, history.index)
                end)

                it("navigates to newer snapshots", function()
                        Quarrel.older()
                        Quarrel.older() -- index is 1
                        Quarrel.newer()
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_equal(2, history.index)
                end)

                it("respects boundary for newer snapshots", function()
                        Quarrel.newer() -- already at 3
                        local history = Quarrel.cache.db.data[test_cwd]
                        assert.are_equal(3, history.index)
                end)

                it("navigates vcs-scoped history correctly", function()
                        clear({ use_vcs = true })

                        scope_stub = stub(H, "get_current_scope", function()
                                return "feat-x"
                        end)

                        local branch_key = test_cwd .. "\0" .. "feat-x"

                        -- setup some history
                        H.update_history(branch_key, { "branch-file1", "foo" }, "append")
                        H.update_history(branch_key, { "branch-file2", "bar" }, "append")

                        Quarrel.older()
                        local branch_history = Quarrel.cache.db.data[branch_key]
                        -- verify navigation acted on the scoped key, not the base cwd
                        assert.are_equal(1, branch_history.index)
                end)

                it("falls back to base key history for an unscoped branch", function()
                        clear({ use_vcs = true })

                        Quarrel.cache.db.data[test_cwd] = {
                                index = 1,
                                entries = { { "/test/base-file" } },
                        }

                        scope_stub = stub(H, "get_current_scope", function()
                                return "feat-x"
                        end)

                        local history, _cwd = H.get_history_context()
                        assert.is_not_nil(history)
                        assert.are_same({ "/test/base-file" }, history.entries[1])
                end)

                it("returns composite key history when it exists", function()
                        clear({ use_vcs = true })

                        local composite = test_cwd .. "\0feat-x"
                        Quarrel.cache.db.data[test_cwd] = {
                                index = 1,
                                entries = { { "/test/base-file" } },
                        }
                        Quarrel.cache.db.data[composite] = {
                                index = 1,
                                entries = { { "/test/branch-file" } },
                        }

                        scope_stub = stub(H, "get_current_scope", function()
                                return "feat-x"
                        end)

                        local history, _cwd = H.get_history_context()
                        assert.is_not_nil(history)
                        assert.are_same({ "/test/branch-file" }, history.entries[1])
                end)
        end)
end)
