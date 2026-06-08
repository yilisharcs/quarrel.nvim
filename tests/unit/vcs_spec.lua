local Quarrel = require("quarrel")
local H = Quarrel.__INTERNAL_H
local t = require("tests.testutil")

describe("VCS scope resolution", function()
        t.setup()
        local temp_root = t.create_temp_dir()
        local with_jj = vim.fs.joinpath(temp_root, "with_jj")
        local with_git = vim.fs.joinpath(temp_root, "with_git")
        local no_vcs = vim.fs.joinpath(temp_root, "no_vcs")

        local mock_jj_available
        local mock_git_available

        local exec_stub, system_stub

        before_each(function()
                mock_jj_available = true
                mock_git_available = true

                vim.fs.rm(with_jj, { recursive = true, force = true })
                vim.fs.rm(with_git, { recursive = true, force = true })
                vim.fs.rm(no_vcs, { recursive = true, force = true })

                vim.fn.mkdir(with_jj, "p")
                vim.fn.mkdir(vim.fs.joinpath(with_jj, ".jj"), "p")
                vim.fn.mkdir(with_git, "p")
                vim.fn.mkdir(no_vcs, "p")

                exec_stub = stub(vim.fn, "executable", function(name)
                        if name == "jj" then
                                return mock_jj_available and 1 or 0
                        end
                        if name == "git" then
                                return mock_git_available and 1 or 0
                        end
                        return 0
                end)

                system_stub = stub(vim, "system", function(_cmd, _opts)
                        return {
                                wait = function()
                                        return { code = 0, stdout = "", stderr = "" }
                                end,
                        }
                end)
        end)

        after_each(function()
                exec_stub:revert()
                system_stub:revert()
        end)

        -- `vim.system()` returns an object with a `wait()` method. caller calls
        -- :wait() to block the job and receive { code, stdout, stderr }. returns
        -- a table whose wait key returns the canned data, mimicking the og shape.
        local function reply(data)
                return {
                        wait = function()
                                return data
                        end,
                }
        end

        -- mocks `vim.system()` with a pattern router: `H.get_current_scope`
        -- calls vim.system with different command arrays for each executable.
        -- the stub concats this table and pattern matches on it to tell which
        -- command is being executed; first match wins. if nothing matches,
        -- return a sensible default, and ignore `data.signal`.
        local function mock_system(patterns)
                stub(vim, "system", function(cmd, _opts)
                        local line = table.concat(cmd, " ")
                        for _, spec in ipairs(patterns) do
                                local pat, data = spec[1], spec[2]
                                if line:match(pat) then
                                        return reply(data)
                                end
                        end
                        return reply({ code = 0, stdout = "", stderr = "" })
                end)
        end

        describe("get_current_scope", function()
                it("returns nil when use_vcs is disabled", function()
                        clear({ use_vcs = false })
                        assert.is_nil(H.get_current_scope(with_jj))
                end)

                describe("jujutsu", function()
                        it("resolves bookmark scope", function()
                                clear({ use_vcs = true })
                                mock_system({
                                        {
                                                "bookmarks",
                                                {
                                                        code = 0,
                                                        stdout = "main\n",
                                                        stderr = "",
                                                },
                                        },
                                })
                                assert.are_equal("main", H.get_current_scope(with_jj))
                        end)

                        it("strips active marker (*) and remote suffix (@origin)", function()
                                clear({ use_vcs = true })
                                mock_system({
                                        {
                                                "bookmarks",
                                                {
                                                        code = 0,
                                                        stdout = "feature*\n@origin/main\n",
                                                        stderr = "",
                                                },
                                        },
                                })
                                assert.are_equal("feature", H.get_current_scope(with_jj))
                        end)

                        it("falls back to change ID when no bookmarks exist", function()
                                clear({ use_vcs = true })
                                mock_system({
                                        {
                                                "bookmarks",
                                                {
                                                        code = 0,
                                                        stdout = "",
                                                        stderr = "",
                                                },
                                        },
                                        {
                                                "change_id",
                                                {
                                                        code = 0,
                                                        stdout = "deadbeef\n",
                                                        stderr = "",
                                                },
                                        },
                                })
                                assert.are_equal("deadbeef", H.get_current_scope(with_jj))
                        end)
                end)

                describe("git", function()
                        it("resolves branch name", function()
                                mock_jj_available = false
                                clear({ use_vcs = true })
                                mock_system({
                                        {
                                                "branch %-%-show%-current",
                                                {
                                                        code = 0,
                                                        stdout = "main\n",
                                                        stderr = "",
                                                },
                                        },
                                })
                                assert.are_equal("main", H.get_current_scope(with_git))
                        end)

                        it("falls back to short SHA on detached HEAD", function()
                                mock_jj_available = false
                                clear({ use_vcs = true })
                                mock_system({
                                        {
                                                "branch %-%-show%-current",
                                                {
                                                        code = 0,
                                                        stdout = "",
                                                        stderr = "",
                                                },
                                        },
                                        {
                                                "rev%-parse",
                                                {
                                                        code = 0,
                                                        stdout = "deadbeef\n",
                                                        stderr = "",
                                                },
                                        },
                                })
                                assert.are_equal("deadbeef", H.get_current_scope(with_git))
                        end)
                end)
        end)
end)
