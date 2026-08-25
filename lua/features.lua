vim.pack.add({"https://github.com/mbbill/undotree",
"https://github.com/folke/which-key.nvim",
})
vim.keymap.set('n', '<leader>U', '<cmd>UndotreeToggle<CR>', { desc = 'Undo tree' })

vim.pack.add({"https://github.com/nvim-mini/mini.nvim"})
require('mini.surround').setup({})
