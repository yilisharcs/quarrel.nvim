# quarrel.nvim

Automagically manage project-local arglists.

## INSTALLATION

Using Neovim's built-in package manager:

```lua
vim.pack.add({
        src = "https://github.com/yilisharcs/quarrel.nvim",
})
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
        "yilisharcs/quarrel.nvim",
        init = function()
                vim.g.quarrel = { --[[ config goes here ]] }
        end
}
```

## INTRODUCTION

_quarrel.nvim_ intends to fix a persistent issue in file navigation: alternate
buffers can't cope with multiple files and global marks are neither unlimited
nor project-local. This plugin leverages the built-in `arglist` to automatically
manage these multiple files. Whenever you change directories, it'll save the
arglist of the previous directory and load the next one's.

### Design

ThePrimeagen's Harpoon is what introduced me to the concept of project-local
marks. After some time -- and a bug that I couldn't track down which prevented
me from embracing the idea completely -- I decided to simplify my init.lua and
use global marks instead, and even opened an issue on GitHub with a snippet of
code that I'd used for a long time, hoping that it would be upstreamed:

**Update global mark position on BufLeave, VimLeavePre**: https://github.com/neovim/neovim/issues/36358

I was quickly disabused of the idea that global marks should remember the
cursor position. They serve a different purpose. I dislike that purpose, but
it is a purpose nonetheless. I decided then that writing this plugin could be
a learning experience in leveraging native solutions over custom special files
and json. Thus, it was born: a minimal wrapper around the `arglist` that stays
out of the way. It maps a directory path to a list of paths and encodes them
into msgpack format with `vim.mpack`. This data is held in-memory until you
exit Nvim (impossible!!), to mean that this plugin does not support multiple
instances writing to the database; the last writer wins.

This diverged from the original goal. This plugin handles neither remembering
the cursor position nor automatically changing directories with heuristics; I
recommend using [MiniMisc](https://github.com/nvim-mini/mini.misc) with \
`setup_auto_root()` and `setup_restore_cursor()` enabled for that. This plugin
does not external track file changes to update the arglist; I recommend using
[yazi.nvim](https://github.com/mikavilpas/yazi.nvim) for that. This plugin
also does not provide a picker for the arglist, and will never have one. It
will remain minimal.

### Commands

##### :Qedit

                        Open a `special-buffer` with 'filetype' quarrel for the
                        current directory's arglist. Edits, additions,
                        removals, and shuffles are committed to the cache on
                        save.

##### :Qolder

                        Navigate to an older snapshot in history. Clears the
                        current `arglist` and replaces it with the previous
                        snapshot. Note that later snapshots will be pruned if
                        an older arglist is edited.

##### :Qnewer

                        Navigate to a newer snapshot in history. Clears the
                        current `arglist` and replaces it with the next
                        snapshot.

### Setup

This plugin works out of the box via 'runtimepath'. It can be configured with \
`vim.g.quarrel` in `init.lua`, and provides a global Lua table for scripting. You
can call `require("quarrel").setup()` to refresh all internal side-effects.

See `Quarrel-configuration` for `config` structure and default values.

### Tips

Leverage built-in Neovim features to make editing more pleasant:
- Edit the `:previous` or `:next` arglist files with `[a` and `a]`.
- `:rewind` to the first or jump to the `:last` arglist files with `[A` and `A]`.
- Operate on the arglist with `:argdo`.

### Disabling

To disable core functionality, set `vim.g.quarrel_disable` (globally) to `true`.

## CONFIGURATION

```lua
---@type quarrel.Opts
vim.g.quarrel = {
    -- Path to the database file where arglists are stored.
    database = vim.fs.joinpath(vim.fn.stdpath("state"), "quarrel/quarrel.msgpack"),
    -- Number of history entries to keep per project.
    hist_level = 3,
    -- Whether to automatically echo the arglist on changes.
    notify = false,
    -- Module mappings. Use '' (empty string) to disable one.
    mappings = {
        -- Add current file to arglist.
        add = "<leader>a",
        -- Edit the arglist.
        edit = "<leader>e",
        -- Go to older arglist.
        older = "<leader>[",
        -- Go to newer arglist.
        newer = "<leader>]",
        -- Go to arg file 1.
        arg1 = "<leader>h",
        -- Go to arg file 2.
        arg2 = "<leader>j",
        -- Go to arg file 3.
        arg3 = "<leader>k",
        -- Go to arg file 4.
        arg4 = "<leader>l",
        -- Go to arg file 5.
        arg5 = "<leader>;",
    },
}
```

## TROUBLESHOOTING

If you encounter issues, please follow these steps:

Run `:checkhealth quarrel` to verify your environment, Nvim version, and
database accessibility.

Use the provided minimal reproduction script to isolate the issue from your
personal configuration:

```bash
just repro
```

Alternatively, run it directly with Neovim:

```bash
nvim --clean -u scripts/repro.lua
```

If the issue persists in the minimal environment, please report it at:
    https://codeberg.org/yilisharcs/quarrel.nvim/issues

## SIMILAR PLUGINS

- [ThePrimeagen/harpoon](https://github.com/ThePrimeagen/harpoon)
- [nvim-mini/mini.visits](https://github.com/nvim-mini/mini.visits)

## LICENSE

Copyright 2025-2026 yilisharcs <yilisharcs@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.