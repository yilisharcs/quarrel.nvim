local Quarrel = require("quarrel")
local H = Quarrel.__INTERNAL_H
local t = require("tests.testutil")

describe("database I/O resilience", function()
    t.setup()
    local temp_root = t.create_temp_dir()
    local test_cwd = vim.fs.joinpath(temp_root, "project")
    vim.fn.mkdir(test_cwd, "p")

    local eligible_stub, notify_stub

    before_each(function()
        vim.uv.chdir(test_cwd)

        eligible_stub = stub(H, "is_eligible", function(path)
            if path:sub(1, 1) == "/" then
                return path
            else
                return "/test/" .. path
            end
        end)

        -- one of the warn messages if write_db_file fails fills
        -- up stdout/err/idk. no need to keep track of that here.
        notify_stub = stub(vim, "notify", function() end)
    end)

    after_each(function()
        eligible_stub:revert()
        notify_stub:revert()
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

    it("aborts on encode failure", function()
        local path = vim.fs.joinpath(temp_root, "encode_fail.msgpack")
        H.write_db_file(path, { data = { function() end } })
        assert.are_same(0, vim.fn.filereadable(path))
    end)

    it("aborts when temporary file cannot be opened", function()
        local open_stub = stub(io, "open", function() end)
        local path = vim.fs.joinpath(temp_root, "no_open.msgpack")
        H.write_db_file(path, { data = "test" })
        open_stub:revert()
        assert.are_same(0, vim.fn.filereadable(path))
    end)
end)

describe("dirty keys merge", function()
    t.setup()
    local temp_root = t.create_temp_dir()

    local eligible_stub, notify_stub

    before_each(function()
        eligible_stub = stub(H, "is_eligible", function(path)
            if path:sub(1, 1) == "/" then
                return path
            else
                return "/test/" .. path
            end
        end)
        notify_stub = stub(vim, "notify", function() end)
    end)

    after_each(function()
        eligible_stub:revert()
        notify_stub:revert()
        H.dirty_keys = {}
    end)

    it("preserves untouched disk entries on write", function()
        local path = vim.fs.joinpath(temp_root, "merge.msgpack")

        -- simulate a database with two projects already on disk
        local on_disk = {
            _meta = { version = 1 },
            data = {
                ["/project_a"] = {
                    index = 1,
                    entries = { { "/project_a/init.lua" } },
                },
                ["/project_b"] = {
                    index = 1,
                    entries = { { "/project_b/main.lua" } },
                },
            },
        }
        H.write_db_file(path, on_disk)
        H.dirty_keys = {}

        -- this instance only modified project_a
        H.dirty_keys["/project_a"] = true
        local mem_data = {
            _meta = { version = 1 },
            data = {
                ["/project_a"] = {
                    index = 1,
                    entries = { { "/project_a/init.lua", "/project_a/new.lua" } },
                },
            },
        }

        H.write_db_file(path, mem_data)

        local result = H.read_db_file(path)
        assert.are_same({ "/project_a/init.lua", "/project_a/new.lua" }, result.data["/project_a"].entries[1])
        assert.are_same({ "/project_b/main.lua" }, result.data["/project_b"].entries[1])
    end)

    it("clears dirty_keys after successful write", function()
        local path = vim.fs.joinpath(temp_root, "clean.msgpack")
        H.dirty_keys["/test"] = true

        H.write_db_file(path, {
            _meta = { version = 1 },
            data = { ["/test"] = { index = 1, entries = { {} } } },
        })

        assert.are_same({}, H.dirty_keys)
    end)
end)
