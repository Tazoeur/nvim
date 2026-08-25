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

vim.pack.add({ 'https://github.com/RRethy/vim-illuminate' })
require('illuminate').configure {
  providers = { 'lsp', 'treesitter', 'regex' },
  delay = 100,
  filetypes_denylist = { 'dirbuf', 'dirvish', 'fugitive' },
  under_cursor = true,
  min_count_to_highlight = 2,
}
