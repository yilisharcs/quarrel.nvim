local Quarrel = require("quarrel")
local H = Quarrel.__INTERNAL_H
local t = require("tests.testutil")

describe("database I/O resilience", function()
        t.setup()
        local temp_root = t.create_temp_dir()
        local test_cwd = vim.fs.joinpath(temp_root, "project")
        vim.fn.mkdir(test_cwd, "p")

        local eligible_stub

        before_each(function()
                vim.uv.chdir(test_cwd)

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
        end)

        it("starts fresh from an empty database file", function()
                local path = vim.fs.joinpath(temp_root, "empty.msgpack")
                io.open(path, "w"):close()

                local db = H.read_db_file(path)
                assert.are_same({ version = 1 }, db._meta)
                assert.are_same({}, db.data)
        end)

        it("falls back to defaults on decode failure", function()
                local path = vim.fs.joinpath(temp_root, "corrupted.msgpack")
                local fp = assert(io.open(path, "wb"), "could not open corrupted.msgpack")
                local invalid_data = "\xff\xfe\x00"
                fp:write(invalid_data)
                fp:close()

                local db = H.read_db_file(path)
                assert.are_same({ version = 1 }, db._meta)
                assert.are_same({}, db.data)
        end)

        it("round-trips database through write and read", function()
                local path = vim.fs.joinpath(temp_root, "cycle.msgpack")
                local original = {
                        _meta = { version = 1 },
                        data = {
                                [test_cwd] = {
                                        index = 1,
                                        entries = { { "/test/file1" } },
                                },
                        },
                }
                H.write_db_file(path, original)

                local reloaded = H.read_db_file(path)
                assert.are_equal(1, reloaded._meta.version)
                assert.are_same(original.data, reloaded.data)
        end)
end)
