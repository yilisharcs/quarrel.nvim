local Quarrel = require("quarrel")
local H = Quarrel.__INTERNAL_H
local t = require("tests.testutil")

describe("symlink resolution", function()
        t.setup()
        local temp_root = t.create_temp_dir()
        local real_dir = vim.fs.joinpath(temp_root, "real")
        local link_dir = vim.fs.joinpath(temp_root, "link")
        local real_file = vim.fs.joinpath(real_dir, "file.txt")
        local link_file = vim.fs.joinpath(temp_root, "file_link.txt")

        before_each(function()
                vim.fn.mkdir(real_dir, "p")
                vim.uv.fs_symlink("real", link_dir, { dir = true })

                local f = io.open(real_file, "w")
                if f then
                        f:write("test")
                        f:close()
                end
                vim.uv.fs_symlink(real_file, link_file)
        end)

        after_each(function()
                vim.fn.delete(temp_root, "rf")
        end)

        it("resolves project root symlinks in H.get_active_key", function()
                local key_real = H.get_active_key(real_dir)
                local key_link = H.get_active_key(link_dir)

                assert.are_equal(key_real, key_link)
                assert.are_equal(real_dir, key_real)
        end)

        it("resolves file symlinks in H.is_eligible", function()
                assert.are_equal("file", vim.uv.fs_stat(real_file).type)
                assert.are_equal("link", vim.uv.fs_lstat(link_file).type)
                local resolved = H.is_eligible(link_file)
                assert.are_equal(real_file, resolved)
        end)

        it("shares history between real and symlinked project paths", function()
                -- use real path
                vim.uv.chdir(real_dir)
                Quarrel.add(real_file)
                Quarrel.write_cache()

                -- use link path
                vim.uv.chdir(link_dir)
                Quarrel.read()

                local argv = vim.fn.argv()
                assert.are_same({ real_file }, argv)
        end)

        it("prevents duplicate entries when adding real and symlinked paths", function()
                vim.uv.chdir(real_dir)
                Quarrel.add(real_file)
                Quarrel.add(link_file)

                local argv = vim.fn.argv()
                assert.are_same({ real_file }, argv)
        end)
end)
