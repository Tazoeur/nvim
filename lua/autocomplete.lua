-- blink.cmp replaces native vim.lsp.completion: it draws its own popup, so it
-- manages completeopt itself. LSP capabilities (advertising snippet support,
-- etc.) are wired up in lsp.lua via blink.cmp.get_lsp_capabilities().
vim.pack.add({ { src = "https://github.com/Saghen/blink.cmp", version = "v1.10.2" } })

require("blink.cmp").setup({
  -- Telescope's prompt is a buftype=prompt buffer; keep blink out of it (and
  -- any other prompt-style picker) entirely.
  enabled = function()
    return vim.bo.buftype ~= "prompt"
  end,

  keymap = {
    preset = "none",
    ["<C-n>"] = { "select_next", "fallback" },
    ["<C-p>"] = { "select_prev", "fallback" },
    ["<C-y>"] = { "select_and_accept" },
    -- Both bound to the same thing: over a terminal (this config runs inside
    -- tmux) Ctrl-Space is unreliable -- many terminals/multiplexers deliver
    -- it as a raw NUL byte, which Neovim reports as <Nul>, not <C-Space>.
    ["<C-space>"] = { "show" },
    ["<Nul>"] = { "show" },
  },

  completion = {
    list = {
      selection = {
        preselect = true, -- first match is highlighted...
        auto_insert = false, -- ...but never written into the buffer until <C-y>
      },
    },
  },

  sources = {
    default = { "lsp", "path", "buffer" },
    per_filetype = {
      sql = { "dadbod", "lsp", "buffer" },
      mysql = { "dadbod", "lsp", "buffer" },
      plsql = { "dadbod", "lsp", "buffer" },
    },
    providers = {
      -- Reuses vim-dadbod-completion's own blink source (table/column/alias
      -- completion) instead of its legacy omnifunc path.
      dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" },
    },
  },
})
