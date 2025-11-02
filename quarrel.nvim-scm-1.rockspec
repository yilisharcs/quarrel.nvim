---@diagnostic disable: lowercase-global

package = "quarrel.nvim"
local repository = package
local namespace = "yilisharcs"

local _MODREV, _SPECREV = "scm", "-1"
version = _MODREV .. _SPECREV
rockspec_format = "3.0"

version = "scm-1"

source = {
        url = ("git+https://github.com/%s/%s"):format(namespace, repository),
        tag = "HEAD",
}

description = {
        summary = "Automagically manage project-local arglists.",
        detailed = [[quarrel.nvim intends to fix a persistent issue in file navigation: alternate
buffers can't cope with multiple files and global marks don't remember cursor
position. This plugin leverages the built-in arglist to automatically manage
these multiple files. Whenever you change directories, it'll save the arglist
of the previous directory and load the next one's.]],
        license = "Apache-2.0",
        homepage = ("https://github.com/%s/%s"):format(namespace, repository),
        issues_url = ("https://github.com/%s/%s/issues"):format(namespace, repository),
        maintainer = "yilisharcs <yilisharcs@gmail.com>",
        labels = {
                "neovim",
                "plugin",
        },
}

dependencies = {
        "lua == 5.1",
}

test_dependencies = {}

build = {
        type = "make",
        build_pass = false,
        install_variables = {
                INST_PREFIX = "$(PREFIX)",
                INST_LUADIR = "$(LUADIR)",
        },
}
