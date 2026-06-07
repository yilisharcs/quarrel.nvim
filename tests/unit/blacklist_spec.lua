local Quarrel = require("quarrel")
local H = Quarrel.__INTERNAL_H
local t = require("tests.testutil")

describe("blacklist", function()
        t.setup()
        local temp_root = t.create_temp_dir()
        local blacklisted_dir = vim.fs.joinpath(temp_root, "blacklisted")
        local allowed_dir = vim.fs.joinpath(temp_root, "allowed")
        local sub_dir = vim.fs.joinpath(blacklisted_dir, "sub")

        before_each(function()
                vim.fn.mkdir(blacklisted_dir, "p")
                vim.fn.mkdir(allowed_dir, "p")
                vim.fn.mkdir(sub_dir, "p")
                vim.uv.chdir(temp_root)
        end)

        it("prevents reading from blacklisted directories", function()
                clear({ blacklist = { blacklisted_dir } })
                vim.uv.chdir(blacklisted_dir)

                -- set some dummy data in cache to verify it's NOT read
                Quarrel.cache.db.data[blacklisted_dir] = {
                        index = 1,
                        entries = { { "file1" } },
                }

                Quarrel.read()
                assert.are.same({}, vim.fn.argv())
        end)

        it("prevents writing to blacklisted directories", function()
                clear({ blacklist = { blacklisted_dir } })
                vim.uv.chdir(blacklisted_dir)

                vim.cmd("argadd file1")
                Quarrel.write_cache()

                assert.is_nil(Quarrel.cache.db.data[blacklisted_dir])
        end)

        it("ignores subdirectories of blacklisted paths", function()
                clear({ blacklist = { blacklisted_dir } })
                vim.uv.chdir(sub_dir)

                Quarrel.add("file1")
                assert.is_nil(Quarrel.cache.db.data[sub_dir])
        end)

        it("allows non-blacklisted directories", function()
                clear({ blacklist = { blacklisted_dir } })
                vim.uv.chdir(allowed_dir)

                Quarrel.add("file1")
                assert.truthy(Quarrel.cache.db.data[allowed_dir])
        end)

        it("supports home-relative paths (~/)", function()
                local home = vim.uv.os_homedir()
                if not home then
                        pending("No home directory found")
                        return
                end

                local home_rel = "~/test_blacklist"
                local abs_path = vim.fs.normalize(home_rel)

                clear({ blacklist = { home_rel } })
                assert.is_true(H.is_blacklisted(abs_path))
        end)
end)
