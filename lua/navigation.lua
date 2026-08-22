vim.pack.add({'https://github.com/stevearc/oil.nvim'})

require("oil").setup()

vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })

vim.pack.add({
"https://github.com/nvim-lua/plenary.nvim", -- dependency for telescope
"https://github.com/nvim-telescope/telescope.nvim"})


require('telescope').setup {
      -- You can put your default mappings / updates / etc. in here
      --  All the info you're looking for is in `:help telescope.setup()`
      --
      defaults = {
        mappings = {
          i = {
            ['<C-s>'] = 'file_split',
          },
        },
      },
      -- pickers = {}
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
      },
    }

    -- Enable Telescope extensions if they are installed
    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')
    pcall(require('telescope').load_extension, 'noice')
    pcall(require('telescope').load_extension, 'neoclip')

    -- See `:help telescope.builtin`
    local builtin = require 'telescope.builtin'
    vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = 'Search help' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = 'Search keymaps' })
    vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = 'Search files' })
    vim.keymap.set('n', '<leader>sF', function()
      builtin.find_files { hidden = true, no_ignore = true, find_command = { 'rg', '--files', '--hidden', '-g', '!.git' } }
    end, { desc = '[S]earch [H]idden files' })
    vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = 'Search select Telescope' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = 'Search current word' })
    vim.keymap.set('n', '<leader>sg', function()
      -- Live grep, but a leading token containing "*" (e.g. "*.sql pattern")
      -- is peeled off and used as a --glob filter instead of search text.
      local finders = require 'telescope.finders'
      local sorters = require 'telescope.sorters'
      local make_entry = require 'telescope.make_entry'
      local conf = require('telescope.config').values
      local flatten = require('telescope.utils').flatten

      local grepper = finders.new_job(function(prompt)
        if not prompt or prompt == '' then
          return nil
        end

        local glob, search = prompt:match '^(%S*%*%S*)%s+(.*)$'
        local extra_args = {}
        if glob then
          extra_args = { '--glob=' .. glob }
        else
          search = prompt
        end

        return flatten { conf.vimgrep_arguments, extra_args, '--', search }
      end, make_entry.gen_from_vimgrep {}, nil, nil)

      require('telescope.pickers').new({}, {
        prompt_title = 'Live Grep',
        finder = grepper,
        previewer = conf.grep_previewer {},
        sorter = sorters.highlighter_only {},
      }):find()
    end, { desc = 'Search by grep (supports "*.ext pattern")' })
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = 'Search diagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = 'Search Resume' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = 'Search Recent Files' })
    vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = 'Find existing buffers' })

    -- Slightly advanced example of overriding default behavior and theme
    vim.keymap.set('n', '<leader>/', function()
      -- You can pass additional configuration to Telescope to change the theme, layout, etc.
      builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        winblend = 10,
        previewer = false,
      })
    end, { desc = '[/] Fuzzily search in current buffer' })

    -- It's also possible to pass additional configuration options.
    --  See `:help telescope.builtin.live_grep()` for information about particular keys
    vim.keymap.set('n', '<leader>s/', function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Live grep in open files',
      }
    end, { desc = 'Search in open files' })

    -- Shortcut for searching your Neovim configuration files
    vim.keymap.set('n', '<leader>sn', function()
      builtin.find_files { cwd = vim.fn.stdpath 'config' }
    end, { desc = 'Search neovim files' })


