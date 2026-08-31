-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--  See `:help wincmd` for a list of all window commands
--  I can't remember where those are set up, but those keybindings are set up somewhere!

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Diagnostic keymaps
vim.keymap.set("n", "<leader>ud", vim.diagnostic.open_float, { desc = "View diagnostic under cursor" })
vim.keymap.set("n", "<leader>uid", function()
	vim.diagnostic.config({ virtual_text = not vim.diagnostic.config().virtual_text })
end, { desc = "Toggle diagnostic virtual text" })

-- Exit terminal mode in the builtif terminal
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

--  Disable arrow keys in normal mode
vim.keymap.set("n", "<left>", '<cmd>echo "Use h to move!!"<CR>')
vim.keymap.set("n", "<right>", '<cmd>echo "Use l to move!!"<CR>')
vim.keymap.set("n", "<up>", '<cmd>echo "Use k to move!!"<CR>')
vim.keymap.set("n", "<down>", '<cmd>echo "Use j to move!!"<CR>')

-- Vertical center after moving up or down
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- Remove previous word
vim.keymap.set("i", "<C-BS>", "<Esc>ciw", { silent = true, desc = "Delete word under cursor" })

vim.keymap.set("n", "<A-l>", "<cmd>cnext<CR>", { desc = "Go to next item in quicklist" })
vim.keymap.set("n", "<A-h>", "<cmd>cprev<CR>", { desc = "Go to previous item in quicklist" })

function reload_config()
	local ok_update, err_update = pcall(vim.cmd, "update")
	if not ok_update then
		vim.api.nvim_err_writeln("Error during `:update` -> " .. tostring(err_update))
		return
	end

	local ok_source, err_source = pcall(vim.cmd, "source ~/.config/nvim/init.lua")
	if not ok_source then
		vim.api.nvim_err_writeln("Error during `:source` -> " .. tostring(err_source))
		return
	end

	vim.notify("Neovim configuration file reloaded", vim.log.levels.INFO)
end
vim.keymap.set("n", "<leader>r", reload_config, { desc = "Reload Neovim configuration" })

vim.keymap.set("n", "<leader>cp", function()
	local file_path = vim.fn.expand("%")
	vim.fn.setreg("+", file_path)
	vim.notify("File path copied to clipboard (" .. file_path .. ")")
end, { desc = "Copy relative file path to clipboard" })

vim.keymap.set("n", "<leader>f", function()
	vim.lsp.buf.format({ async = true })
end, { desc = "Format buffer" })

vim.keymap.set("n", "<leader>q", ":enew<bar>bd #<CR>", { desc = "Close current buffer" })
vim.keymap.set("n", "<leader>Q", ":qa<CR>", { desc = "Close everything" })
