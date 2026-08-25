vim.pack.add({"https://github.com/rose-pine/neovim"})

require("rose-pine").setup({})
vim.cmd('colorscheme rose-pine')

vim.pack.add(
  {  'https://github.com/nvim-tree/nvim-web-devicons',
   "https://github.com/nvim-mini/mini.icons",
   "https://github.com/folke/snacks.nvim",
   }
)

--[[
--- Add the startup section
---@param opts? {icon?:string}
---@return snacks.dashboard.Section?
function M.sections.startup(opts)
  opts = opts or {}
  M.lazy_stats = M.lazy_stats and M.lazy_stats.startuptime > 0 and M.lazy_stats or require("lazy.stats").stats()
  local ms = (math.floor(M.lazy_stats.startuptime * 100 + 0.5) / 100)
  local icon = opts.icon or "⚡ "
  return {
    align = "center",
    text = {
      { icon .. "Neovim loaded ", hl = "footer" },
      { M.lazy_stats.loaded .. "/" .. M.lazy_stats.count, hl = "special" },
      { " plugins in ", hl = "footer" },
      { ms .. "ms", hl = "special" },
    },
  }
end
--]]
require('snacks').setup( {
	animate = { enabled = true},
	bigfile = {enabled = true},
	dashboard = {enabled = true, 
	preset = {
    keys = {
      { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
      { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
      { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
      { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
      { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
      { icon = " ", key = "s", desc = "Restore Session", section = "session" },
      { icon = " ", key = "u", desc = "Update packages", action=":lua vim.pack.update()" },
      { icon = " ", key = "q", desc = "Quit", action = ":qa" },
    },},

	sections = {
    { section = "header" },
    { section = "keys",  padding = 1 },
    {
      icon = " ",
      title = "Git Status",
      section = "terminal",
      enabled = function()
        return Snacks.git.get_root() ~= nil
      end,
      cmd = "git status --short --branch --renames",
      height = 5,
      padding = 1,
      ttl = 5 * 60,
      indent = 3,
    } 
  } },
	notifier = {enabled = true}
}
)

vim.keymap.set('n', '<leader>un', function() Snacks.notifier.show_history() end, { desc = 'UI: notification history' })

--[[
return {
  'RRethy/vim-illuminate',
  config = function()
    require('illuminate').configure {
      -- providers: provider used to get references in the buffer, ordered by priority
      providers = {
        'lsp',
        'treesitter',
        'regex',
      },
      -- delay: delay in milliseconds
      delay = 100,
      -- filetype_overrides: filetype specific overrides.
      -- The keys are strings to represent the filetype while the values are tables that
      -- supports the same keys passed to .configure except for filetypes_denylist and filetypes_allowlist
      filetype_overrides = {},
      -- filetypes_denylist: filetypes to not illuminate, this overrides filetypes_allowlist
      filetypes_denylist = {
        'dirbuf',
        'dirvish',
        'fugitive',
      },
      -- filetypes_allowlist: filetypes to illuminate, this is overridden by filetypes_denylist
      -- You must set filetypes_denylist = {} to override the defaults to allow filetypes_allowlist to take effect
      filetypes_allowlist = {},
      -- modes_denylist: modes to not illuminate, this overrides modes_allowlist
      -- See `:help mode()` for possible values
      modes_denylist = {},
      -- modes_allowlist: modes to illuminate, this is overridden by modes_denylist
      -- See `:help mode()` for possible values
      modes_allowlist = {},
      -- providers_regex_syntax_denylist: syntax to not illuminate, this overrides providers_regex_syntax_allowlist
      -- Only applies to the 'regex' provider
      -- Use :echom synIDattr(synIDtrans(synID(line('.'), col('.'), 1)), 'name')
      providers_regex_syntax_denylist = {},
      -- providers_regex_syntax_allowlist: syntax to illuminate, this is overridden by providers_regex_syntax_denylist
      -- Only applies to the 'regex' provider
      -- Use :echom synIDattr(synIDtrans(synID(line('.'), col('.'), 1)), 'name')
      providers_regex_syntax_allowlist = {},
      -- under_cursor: whether or not to illuminate under the cursor
      under_cursor = true,
      -- large_file_cutoff: number of lines at which to use large_file_config
      -- The `under_cursor` option is disabled when this cutoff is hit
      large_file_cutoff = nil,
      -- large_file_config: config to use for large files (based on large_file_cutoff).
      -- Supports the same keys passed to .configure
      -- If nil, vim-illuminate will be disabled for large files.
      large_file_overrides = nil,
      -- min_count_to_highlight: minimum number of matches required to perform highlighting
      min_count_to_highlight = 2,
      -- should_enable: a callback that overrides all other settings to
      -- enable/disable illumination. This will be called a lot so don't do
      -- anything expensive in it.
      should_enable = function(bufnr)
        return true
      end,
      -- case_insensitive_regex: sets regex case sensitivity
      case_insensitive_regex = false,
    }
  end,
}

-- Collection of various small independent plugins/modules
-- https://github.com/echasnovski/mini.nvim
return {
  'echasnovski/mini.nvim',
  config = function()
    -- Better Around/Inside textobjects
    --
    -- Examples:
    --  - va)  - [V]isually select [A]round [)]paren
    --  - yinq - [Y]ank [I]nside [N]ext [Q]uote
    --  - ci'  - [C]hange [I]nside [']quote
    require('mini.ai').setup { n_lines = 50 }

    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    --
    -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
    -- - sd'   - [S]urround [D]elete [']quotes
    -- - sr)'  - [S]urround [R]eplace [)] [']
    require('mini.surround').setup()

    -- Simple and easy statusline.
    --  You could remove this setup call if you don't like it,
    --  and try some other statusline plugin
    local statusline = require 'mini.statusline'
    -- set use_icons to true if you have a Nerd Font
    statusline.setup { use_icons = vim.g.have_nerd_font }
    -- You can configure sections in the statusline by overriding their
    -- default behavior. For example, here we set the section for
    -- cursor location to LINE:COLUMN
    ---@diagnostic disable-next-line: duplicate-set-field
    statusline.section_location = function()
      return '%2l:%-2v'
    end

    -- Icons ?
    require('mini.icons').setup()
  end,
}

--]]
