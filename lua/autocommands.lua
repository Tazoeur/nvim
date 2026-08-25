-- COMMIT_EDITMSG is the filename that Git uses for commit messages when you run
-- commands like `git commit` without `-m`. The commit message is temporarily
-- stored in a file named .git/COMMIT_EDITMSG. Once you save and close the file,
-- Git reads its contents as the commit message. This approach avoids issue with
-- using `FileType` which is an event that editorconfig overrides.
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
	pattern = "COMMIT_EDITMSG",
	callback = function()
		vim.schedule(function()
			vim.opt_local.textwidth = 80
		end)
	end,
})


-- Add keymaps when attaching LSP
vim.api.nvim_create_autocmd('LspAttach', {
	callback = function(args)
		local bufnr = args.buf ---@type number
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client:supports_method('textDocument/inlayHint') then
			vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
			vim.keymap.set('n', '<leader><leader>lh', function()
				vim.lsp.inlay_hint.enable(
					not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }),
					{ bufnr = bufnr }
				)
			end, { buffer = bufnr, desc = "toggle inlay hints" })
		end
	end,
})


-- vim-dadbod-ui's drawer tree (autoload/db_ui/drawer.vim) indents each
-- nesting level by `shiftwidth()` spaces. Since shiftwidth isn't set
-- globally it falls back to the default tabstop of 8, making the
-- connection/schema/table tree needlessly wide -- so give the drawer's own
-- filetype a smaller shiftwidth instead of changing it everywhere.
vim.api.nvim_create_autocmd('FileType', {
	pattern = 'dbui',
	callback = function()
		vim.opt_local.shiftwidth = 2
	end,
})


-- Highlight when yanking (copying) text
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
  pattern = '*',
})

