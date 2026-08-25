vim.pack.add({"https://github.com/mbbill/undotree",
"https://github.com/folke/which-key.nvim",
})
vim.keymap.set('n', '<leader>U', '<cmd>UndotreeToggle<CR>', { desc = 'Undo tree' })

vim.pack.add({"https://github.com/nvim-mini/mini.nvim"})
require('mini.icons').setup()
require('mini.surround').setup({})
require("mini.ai").setup { n_line = 50 }
local statusline = require("mini.statusline")
statusline.setup{use_icons = vim.g.have_nerd_font }
