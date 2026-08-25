-- Neovim's `require` resolves a module to the FIRST match across
-- 'runtimepath' (via package.path, built from it in rtp order) -- our
-- config directory precedes vim.pack's plugin dirs there, so a module at
-- this same path fully shadows vim-dadbod-completion's own
-- lua/vim_dadbod_completion/blink.lua instead of complementing it: this is
-- a verbatim copy of it, plus enriching column ('C') items with the real
-- type/description from lua/bq_schema.lua's lazily-fetched cache (falling
-- back to the plugin's own generic info/menu text when that cache doesn't
-- have an answer yet -- see bq_schema.lua for what fills it, and when).
--
-- Upstream: https://github.com/kristijanhusak/vim-dadbod-completion/blob/master/lua/vim_dadbod_completion/blink.lua
---@type blink.cmp.Source
local M = {}

local bq_schema = require("bq_schema")

local map_kind_to_cmp_lsp_kind = {
	F = 3, -- Function -> Function
	C = 5, -- Column -> Field
	A = 6, -- Alias -> Variable
	T = 7, -- Table -> Class
	R = 14, -- Reserved -> Keyword
	S = 19, -- Schema -> Folder
}

function M.new()
	return setmetatable({}, { __index = M })
end

function M:get_trigger_characters()
	return { '"', "`", "[", "]", "." }
end

function M:enabled()
	local filetypes = { "sql", "mysql", "plsql" }
	return vim.tbl_contains(filetypes, vim.bo.filetype)
end

-- Not part of upstream. The current buffer's own bigquery dataset (from
-- b:db, e.g. auto-attached per dbt model -- see database.lua's
-- auto_attach_dataset), if any: a column item's `info` string is always
-- "<table> table column" (see vim-dadbod-completion's own
-- s:map_item/s:cache_table_columns), so the table is recovered from that
-- rather than needing our own scope/alias resolution -- reusing whatever
-- vim-dadbod-completion already figured out instead of redoing it.
local function current_dataset()
	local url = vim.b.db
	if not url or url == "" then
		return nil
	end
	return url:match("^bigquery://[^:/]*:([^/]*)$")
end

local function enrich(item, label, doc)
	local dataset = current_dataset()
	local table_name = item.info and item.info:match("^(.+) table column$")
	local meta = dataset and table_name and bq_schema.get(dataset, table_name, item.word)
	if not meta then
		return label, doc
	end
	return meta.type or label, meta.description or doc
end

function M:get_completions(ctx, callback)
	local cursor_col = ctx.cursor[2]
	local line = ctx.line
	local word_start = cursor_col + 1

	local triggers = self:get_trigger_characters()
	while word_start > 1 do
		local char = line:sub(word_start - 1, word_start - 1)
		if vim.tbl_contains(triggers, char) or char:match("%s") then
			break
		end
		word_start = word_start - 1
	end

	-- Get text from word start to cursor
	local input = line:sub(word_start, cursor_col)

	if input ~= "" and input:match("[^0-9A-Za-z_]+") then
		input = ""
	end

	local transformed_callback = function(items)
		callback({
			context = ctx,
			is_incomplete_forward = true,
			is_incomplete_backward = true,
			items = items,
		})
	end

	local results = vim.api.nvim_call_function("vim_dadbod_completion#omni", { 0, input })

	if not results then
		transformed_callback({})
		return function() end
	end

	local by_word = {}
	for _, item in ipairs(results) do
		local key = item.word .. item.kind
		if by_word[key] == nil then
			by_word[key] = item
		end
	end
	local items = {} ---@type table<string,lsp.CompletionItem>

	for _, item in pairs(by_word) do
		local label_desc, doc = item.menu, item.info or ""
		if item.kind == "C" then
			label_desc, doc = enrich(item, label_desc, doc)
		end
		table.insert(items, {
			label = item.abbr or item.word,
			dup = 0,
			insertText = item.word,
			labelDetails = label_desc and { description = label_desc } or nil,
			documentation = doc,
			kind = map_kind_to_cmp_lsp_kind[item.kind] or vim.lsp.protocol.CompletionItemKind.Text,
		})
	end

	transformed_callback(items)

	return function() end
end

return M
