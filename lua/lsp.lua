vim.pack.add({ "https://github.com/j-hui/fidget.nvim" })
require("fidget").setup({})

-- blink.cmp is set up in autocomplete.lua; loading it here too is a harmless
-- no-op (vim.pack.add dedupes by URL) and lets every server pick up its LSP
-- capabilities (snippet support, etc.) below.
vim.pack.add({ { src = "https://github.com/Saghen/blink.cmp", version = "v1.10.2" } })
vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })

--  This function gets run when an LSP attaches to a particular buffer.
--    That is to say, every time a new file is opened that is associated with
--    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
--    function will be executed to configure the current buffer
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
	callback = function(event)
		-- NOTE: Remember that Lua is a real programming language, and as such it is possible
		-- to define small helper and utility functions so you don't have to repeat yourself.
		--
		-- In this case, we create a function that lets us more easily define mappings specific
		-- for LSP related items. It sets the mode, buffer and description for us each time.
		local map = function(keys, func, desc, mode)
			mode = mode or "n"
			vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
		end

		-- Rename the variable under your cursor.
		--  Most Language Servers support renaming across files, etc.
		map("grn", vim.lsp.buf.rename, "Rename")

		-- Execute a code action, usually your cursor needs to be on top of an error
		-- or a suggestion from your LSP for this to activate.
		map("gra", vim.lsp.buf.code_action, "Goto code action", { "n", "x" })

		-- WARN: This is not Goto Definition, this is Goto Declaration.
		--  For example, in C this would take you to the header.
		map("grD", vim.lsp.buf.declaration, "Goto declaration")

		-- The following two autocommands are used to highlight references of the
		-- word under your cursor when your cursor rests there for a little while.
		--    See `:help CursorHold` for information about when this is executed
		--
		-- When you move your cursor, the highlights will be cleared (the second autocommand).
		local client = vim.lsp.get_client_by_id(event.data.client_id)
		if client and client:supports_method("textDocument/documentHighlight", event.buf) then
			local highlight_augroup = vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				buffer = event.buf,
				group = highlight_augroup,
				callback = vim.lsp.buf.document_highlight,
			})

			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				buffer = event.buf,
				group = highlight_augroup,
				callback = vim.lsp.buf.clear_references,
			})

			vim.api.nvim_create_autocmd("LspDetach", {
				group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
				callback = function(event2)
					vim.lsp.buf.clear_references()
					vim.api.nvim_clear_autocmds({ group = "kickstart-lsp-highlight", buffer = event2.buf })
				end,
			})
		end

		-- The following code creates a keymap to toggle inlay hints in your
		-- code, if the language server you are using supports them
		--
		-- This may be unwanted, since they displace some of your code
		if client and client:supports_method("textDocument/inlayHint", event.buf) then
			map("<leader>th", function()
				vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
			end, "Toggle inlay hints")
		end
	end,
})

-- root_dir string -> {project_id=.., location=..} for a DBUI-opened bqls
-- root (see the `bqls` server config below), read back by that config's
-- own `on_init`.
local bqls_dbui_settings = {}

-- Enable the following language servers
--  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
--  See `:help lsp-config` for information about keys and how to configure
---@type table<string, vim.lsp.Config>
local servers = {
	-- clangd = {},
	-- gopls = {},
	-- pyright = {},
	ty = {},
	rust_analyzer = {},
	--
	-- Some languages (like typescript) have entire language plugins that can be useful:
	--    https://github.com/pmizio/typescript-tools.nvim
	--
	-- But for many setups, the LSP (`ts_ls`) will work just fine
	-- ts_ls = {},

	stylua = {}, -- Used to format Lua code

	-- bqls (BigQuery language server) defaults to `gcloud config get
	-- project` and location "US". DBUI's ad-hoc query/table buffers (see
	-- vim-dadbod-ui's autoload/db_ui/query.vim setup_buffer, which sets
	-- b:dbui_db_key_name on every one it opens) live in temp files with no
	-- `.git` -- bqls's only root_marker -- so without this they'd fall
	-- back to whatever root Neovim's cwd resolves to and inherit the
	-- gcloud default, wrong for these buffers' actual (BigQuery) project.
	--
	-- Give each such buffer's BigQuery project its own synthetic root (so
	-- it gets its own bqls client, one per project) and push the real
	-- settings via `on_init`. That runs right after the client's
	-- `initialize` response and strictly before Neovim's first
	-- `textDocument/didOpen` for any of its buffers (see
	-- vim.lsp.Client:_initialize/`on_attach` in the Neovim runtime) --
	-- doing this from `LspAttach` instead is too late: didOpen has already
	-- fired with the wrong project by then, bqls's first diagnostics pass
	-- already ran against it, and it doesn't recompute just because config
	-- changed afterward.
	--
	-- A dbt model or any other .sql file inside a real git repo still
	-- resolves its root via `.git` as normal, untouched by this.
	bqls = {
		root_dir = function(bufnr, on_dir)
			local db_url = vim.b[bufnr].dbui_db_key_name and vim.b[bufnr].db
			local project = db_url and db_url:match("^bigquery://([^:/]*)")
			if not project or project == "" then
				on_dir(vim.fs.root(bufnr, { ".git" }))
				return
			end
			local root = "bqls-dbui://" .. project
			local region = vim.g.vim_dadbod_completion_bigquery_region
			bqls_dbui_settings[root] = {
				project_id = project,
				location = region and region:match("^region%-(.+)$"),
			}
			on_dir(root)
		end,
		on_init = function(client)
			local settings = bqls_dbui_settings[client.config.root_dir]
			if settings then
				client:notify("workspace/didChangeConfiguration", { settings = settings })
			end
			-- bqls's own dry-run cost estimate (the "This query will process
			-- ... when run" window/showMessage) only fires from its
			-- textDocument/didSave handler -- database.lua's own live estimate
			-- (b:bq_estimate in the statusline) already runs the identical dry
			-- run on every edit, so bqls's copy is pure waste, not just a
			-- redundant popup. bqls's `initialize` response declares
			-- textDocumentSync as a bare sync-kind number rather than a full
			-- options object, so Neovim's client fills in the missing `save`
			-- as enabled ({includeText = false}) by default, which is what
			-- causes every :w to actually forward textDocument/didSave to it.
			-- Clearing that here (before any save can happen) makes Neovim
			-- never send didSave to this client at all, so bqls's dry run
			-- (and its redundant diagnostics-on-save pass -- diagnostics
			-- already refresh continuously via didChange) never runs.
			if client.server_capabilities.textDocumentSync then
				client.server_capabilities.textDocumentSync.save = false
			end
		end,
	},

	-- Special Lua Config, as recommended by neovim help docs
	lua_ls = {
		on_init = function(client)
			client.server_capabilities.documentFormattingProvider = false -- Disable formatting (formatting is done by stylua)

			if client.workspace_folders then
				local path = client.workspace_folders[1].name
				if
					path ~= vim.fn.stdpath("config")
					and (vim.uv.fs_stat(path .. "/.luarc.json") or vim.uv.fs_stat(path .. "/.luarc.jsonc"))
				then
					return
				end
			end

			local current_settings = client.config.settings --[[@as lspconfig.settings.lua_ls]]
			client.config.settings.Lua = vim.tbl_deep_extend("force", current_settings.Lua, {
				runtime = {
					version = "LuaJIT",
					path = { "lua/?.lua", "lua/?/init.lua" },
				},
				workspace = {
					checkThirdParty = false,
					-- NOTE: this is a lot slower and will cause issues when working on your own configuration.
					--  See https://github.com/neovim/nvim-lspconfig/issues/3189
					library = vim.api.nvim_get_runtime_file("", true),
				},
			})
		end,
		---@type lspconfig.settings.lua_ls
		settings = {
			Lua = {
				format = { enable = false }, -- Disable formatting (formatting is done by stylua)
			},
		},
	},
}

vim.pack.add({
	"https://github.com/neovim/nvim-lspconfig",
	"https://github.com/mason-org/mason.nvim",
	"https://github.com/mason-org/mason-lspconfig.nvim",
	"https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim",
})

-- Automatically install LSPs and related tools to stdpath for Neovim
require("mason").setup({})

-- Translates between nvim-lspconfig server names and mason.nvim package names (e.g. lua_ls <-> lua-language-server)
require("mason-lspconfig").setup({
	automatic_enable = false, -- Change this to true if you want to automatically enable servers that are installed manually (e.g. via :Mason / :MasonInstall)
})

-- Ensure the servers and tools above are installed
--
-- To check the current status of installed tools and/or manually install
-- other tools, you can run
--    :Mason
--
-- You can press `g?` for help in this menu.
local ensure_installed = vim.tbl_keys(servers or {})
vim.list_extend(ensure_installed, {
	-- You can add other tools here that you want Mason to install
})

require("mason-tool-installer").setup({ ensure_installed = ensure_installed })

for name, server in pairs(servers) do
	vim.lsp.config(name, server)
	vim.lsp.enable(name)
end

vim.pack.add({
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
})
vim.api.nvim_create_autocmd("PackChanged", {
	callback = function(ev)
		local name, kind = ev.data.spec.name, ev.data.kind
		if name == "nvim-treesitter" and kind == "update" then
			if not ev.data.active then
				vim.cmd.packadd("nvim-treesitter")
			end
			vim.cmd("TSUpdate")
		end
	end,
})

local ts_langs = { "lua", "vim", "vimdoc", "query", "markdown", "markdown_inline", "yaml" }
require("nvim-treesitter").install(ts_langs)
vim.api.nvim_create_autocmd("FileType", {
	pattern = ts_langs,
	callback = function()
		vim.treesitter.start()
	end,
})
