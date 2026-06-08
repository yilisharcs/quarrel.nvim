local Quarrel = require("quarrel")
local H = Quarrel.__INTERNAL_H
local t = require("tests.testutil")

describe("downgrade compatibility", function()
        t.setup()
        local temp_root = t.create_temp_dir()
        local test_cwd = vim.fs.joinpath(temp_root, "project")
        vim.fn.mkdir(test_cwd, "p")

        local original_is_eligible = H.is_eligible

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
        end)

        describe("composite key mirroring", function()
                it("writes to base key when composite key is used and entries match", function()
                        local composite = test_cwd .. "\0feat-x"
                        H.update_history(composite, { "file1" }, "append")
                        H.update_history(composite, { "file2" }, "append")

                        assert.are_same(
                                Quarrel.cache.db.data[composite],
                                Quarrel.cache.db.data[test_cwd]
                        )
                end)

                it("does not mirror when key has no null byte", function()
                        H.update_history(test_cwd, { "file1" }, "append")

                        assert.is_not_nil(Quarrel.cache.db.data[test_cwd])
                        for key in pairs(Quarrel.cache.db.data) do
                                assert.is_nil(key:match("%z"))
                        end
                end)

                it("avoids duplicating snapshots across scoped and base keys", function()
                        local composite = test_cwd .. "\0feat-x"
                        H.update_history(composite, { "file1" }, "append")
                        H.update_history(composite, { "file1" }, "append")

                        assert.are_equal(1, #Quarrel.cache.db.data[composite].entries)
                        assert.are_equal(1, #Quarrel.cache.db.data[test_cwd].entries)
                end)
        end)

end)
