vim.pack.add({"https://github.com/mbbill/undotree",
"https://github.com/folke/which-key.nvim",
})
vim.keymap.set('n', '<leader>u', '<cmd>UndotreeToggle<CR>', { desc = 'Undo tree' })
