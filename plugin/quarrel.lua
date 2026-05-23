if vim.g.loaded_quarrel == 1 then
        return
end
vim.g.loaded_quarrel = 1

require("quarrel").setup()
