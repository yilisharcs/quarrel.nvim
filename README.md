# quarrel.nvim

Automagically manage project-local arglists.

## Installation

Using Neovim's built-in package manager:

```lua
vim.pack.add({
    {
        src = "https://github.com/yilisharcs/quarrel.nvim",
    },
})
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "yilisharcs/quarrel.nvim",
}
```

## Configuration

Below are the available options and their default values:

```lua
vim.g.quarrel = {
    -- Where all arg data is stored.
    database = vim.fs.joinpath(vim.fn.stdpath("data"), "quarrel/arglists.msgpack"),

    -- Five opt-in keymaps I believe make for a good workflow.
    -- See for yourself: ./plugin/quarrel.lua:26
    keymaps = false,
}
```

## Usage

quarrel.nvim intends to fix a persistent issue in file navigation: alternate
buffers can't cope with multiple files and global marks don't remember cursor
position. This plugin leverages the built-in arglist to automatically manage
these multiple files. Whenever you change directories, it'll save the arglist
of the previous directory and load the next one's.

> [!TIP]
>
> Leverage built-in Neovim features to make navigation more pleasant:
>
> - Edit the previous or next arglist files with `[a` and `a]`
> - Jump to the first or last arglist files with `[A` and `A]`
> - Operate on the arglist with `:argdo`

Important to note that this plugin does not:
- Change directories automatically. Use [mini.misc](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-misc.md) with `setup_auto_root()`.
- Provide a UI to modify the arglist. Use [fzf-lua](https://github.com/ibhagwan/fzf-lua) with `:FzfLua args`.

> [!NOTE]
>
> quarrel.nvim was initially made to experiment with the arglist. Now it includes
> experimenting with the msgpack format since it takes less space than json and I
> wanted to see what it's like to use it. It will remain minimal.

## See also

Harpoon: <https://github.com/ThePrimeagen/harpoon>

## License

This project is licensed under the [Apache License 2.0](doc/LICENSE).
