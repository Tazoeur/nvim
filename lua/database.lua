-- BigQuery query editor: vim-dadbod runs `:DB`/save-and-execute queries through
-- the `bq` CLI (its built-in bigquery adapter), vim-dadbod-ui gives a results
-- panel + connection drawer, vim-dadbod-completion adds table/keyword completion.
-- Requires `bq`/`gcloud` installed and authenticated (`gcloud auth login`).
vim.pack.add({
	"https://github.com/tpope/vim-dadbod",
	"https://github.com/kristijanhusak/vim-dadbod-ui",
	"https://github.com/kristijanhusak/vim-dadbod-completion",
})

-- See autoload/db/adapter/bigquery.vim: adds #tables() on top of a verbatim
-- copy of vim-dadbod's own bigquery adapter (Neovim only ever loads one
-- autoload/db/adapter/bigquery.vim, so it can't be "official file + extra
-- file").

vim.g.db_ui_use_nerd_fonts = 1
vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
vim.g.db_ui_show_help = 0

-- One connection per line. Project-only connections need fully-qualified
-- table names in queries (`project.dataset.table`); add ':dataset' to a
-- connection to get a default dataset (and table-name completion for it).
vim.g.dbs = {
	{ name = "bigquery-happyhoursmarketdev", url = "bigquery://happyhoursmarketdev" },
}

local dbt = require("dbt")

-- Resolves dbt Jinja (see lua/dbt.lua) when `bufnr` is a dbt model, via
-- `dbt compile`; calls back with the SQL unchanged for a plain .sql file.
-- callback(sql) on success, callback(nil, err) if dbt couldn't compile it.
local function resolve_sql(bufnr, sql, callback)
	local root = dbt.project_root(bufnr)
	if not root then
		callback(sql)
		return
	end
	dbt.compile(sql, root, callback)
end

-- Cost estimate, à la BigQuery console: `bq query --dry_run` reports the
-- bytes the query would scan without running it. Dry runs are free (no
-- bytes billed, no job actually run) -- it's the same call the BigQuery
-- console makes on every keystroke -- so it's safe to run automatically.
local function human_bytes(n)
	local units = { "B", "KB", "MB", "GB", "TB", "PB" }
	local i = 1
	while n >= 1024 and i < #units do
		n = n / 1024
		i = i + 1
	end
	return string.format("%.2f %s", n, units[i])
end

local function find_bytes_processed(value)
	if type(value) ~= "table" then
		return nil
	end
	if value.totalBytesProcessed then
		return tonumber(value.totalBytesProcessed)
	end
	for _, v in pairs(value) do
		local found = find_bytes_processed(v)
		if found then
			return found
		end
	end
	return nil
end

local function bq_flags_from_url(url)
	local project, dataset = url:match("^bigquery://([^:/]*):?([^/]*)$")
	local flags = {}
	if project and project ~= "" then
		table.insert(flags, "--project_id=" .. project)
	end
	if dataset and dataset ~= "" then
		table.insert(flags, "--dataset_id=" .. dataset)
	end
	return flags
end

-- dadbod (vim-dadbod/-ui/-completion) is dialect-agnostic: the same sql/
-- mysql/plsql buffer could be wired to Postgres, MySQL, SQLite, etc. Only
-- run bq-specific machinery (dry-run estimate, dbt compile) when the
-- buffer's connection is actually bigquery -- otherwise leave those
-- backends' own dadbod/dadbod-completion behavior alone, untouched.
local function is_bigquery_target(bufnr)
	local url = vim.b[bufnr].db
	if url == nil or url == "" then
		url = vim.g.db
	end
	if url and url ~= "" then
		return url:match("^bigquery:") ~= nil
	end
	return true -- no connection set: a bare .sql file, this feature's original scope
end

-- callback(bytes) on success, callback(nil, stderr) on failure (e.g. the
-- query is invalid/incomplete, which is expected while it's being typed).
local function dry_run(sql, db_url, callback)
	local cmd = { "bq", "--headless", "--format=json" }
	vim.list_extend(cmd, bq_flags_from_url(db_url or ""))
	vim.list_extend(cmd, { "query", "--nouse_legacy_sql", "--dry_run" })

	vim.system(cmd, { stdin = sql, text = true }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				callback(nil, res.stderr)
				return
			end
			local ok, decoded = pcall(vim.json.decode, res.stdout)
			callback(ok and find_bytes_processed(decoded) or nil)
		end)
	end)
end

local function estimate_query_cost(line1, line2)
	local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
	local sql = table.concat(lines, "\n")
	if vim.trim(sql) == "" then
		vim.notify("BigQuery: no query to estimate", vim.log.levels.WARN)
		return
	end
	if not is_bigquery_target(0) then
		vim.notify("BigQuery: current connection (b:db) isn't bigquery, skipping", vim.log.levels.WARN)
		return
	end
	resolve_sql(0, sql, function(resolved, dbt_err)
		if not resolved then
			vim.notify("BigQuery: dbt couldn't compile this query: " .. (dbt_err or "unknown error"), vim.log.levels.ERROR)
			return
		end
		dry_run(resolved, vim.b.db, function(bytes, err)
			if not bytes then
				vim.notify("BigQuery dry-run failed: " .. (err or "could not parse dry-run output"), vim.log.levels.ERROR)
				return
			end
			vim.notify(("BigQuery: this query will process %s when run"):format(human_bytes(bytes)))
		end)
	end)
end

vim.api.nvim_create_user_command("BqDryRun", function(cmdopts)
	estimate_query_cost(cmdopts.line1, cmdopts.line2)
end, { range = "%" })

vim.keymap.set("n", "<leader>bc", "<cmd>BqDryRun<CR>", { desc = "BigQuery: estimate query cost" })
-- Plain ':' (not <Cmd>) so Vim prepends the visual range ('<,'>) automatically.
vim.keymap.set("x", "<leader>bc", ":BqDryRun<CR>", { desc = "BigQuery: estimate query cost (selection)" })

-- Opens `text` in a new scratch split (sql filetype, never written to disk)
-- and leaves it as the current buffer for the caller to finish setting up.
local function open_scratch_sql(text)
	vim.cmd("botright new")
	vim.bo.buftype = "nofile"
	vim.bo.bufhidden = "wipe"
	vim.bo.swapfile = false
	vim.bo.filetype = "sql"
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(text, "\n"))
end

-- Deliberately RUNS the query for real (not a dry-run): resolves dbt Jinja
-- if applicable, then executes via vim-dadbod's own :DB (so results land in
-- the usual dbout split), in a throwaway scratch buffer -- never the model
-- source file itself, and it shows the exact resolved SQL being run.
local function run_query(line1, line2)
	local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
	local sql = table.concat(lines, "\n")
	if vim.trim(sql) == "" then
		vim.notify("BigQuery: no query to run", vim.log.levels.WARN)
		return
	end
	if not is_bigquery_target(0) then
		vim.notify("BigQuery: current connection (b:db) isn't bigquery, skipping", vim.log.levels.WARN)
		return
	end
	local db_url = vim.b.db
	if not db_url or db_url == "" then
		db_url = vim.g.db
	end
	if not db_url or db_url == "" then
		vim.notify(
			"BigQuery: no connection set -- set one via DBUI or `let b:db = 'bigquery://project:dataset'`",
			vim.log.levels.ERROR
		)
		return
	end
	resolve_sql(0, sql, function(resolved, dbt_err)
		if not resolved then
			vim.notify("BigQuery: dbt couldn't compile this query: " .. (dbt_err or "unknown error"), vim.log.levels.ERROR)
			return
		end
		open_scratch_sql(resolved)
		vim.b.db = db_url
		vim.cmd("%DB")
	end)
end

vim.api.nvim_create_user_command("BqRun", function(cmdopts)
	run_query(cmdopts.line1, cmdopts.line2)
end, { range = "%" })

vim.keymap.set("n", "<leader>bR", "<cmd>BqRun<CR>", { desc = "BigQuery: run query for real" })
vim.keymap.set("x", "<leader>bR", ":BqRun<CR>", { desc = "BigQuery: run query for real (selection)" })

-- Just shows the SQL dbt would actually run (ref/source/config/macros
-- resolved), read-only, without running anything -- no bq/connection
-- involved at all.
local function show_compiled(line1, line2)
	local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
	local sql = table.concat(lines, "\n")
	if vim.trim(sql) == "" then
		vim.notify("BigQuery: nothing to compile", vim.log.levels.WARN)
		return
	end
	resolve_sql(0, sql, function(resolved, dbt_err)
		if not resolved then
			vim.notify("BigQuery: dbt couldn't compile this query: " .. (dbt_err or "unknown error"), vim.log.levels.ERROR)
			return
		end
		open_scratch_sql(resolved)
		vim.bo.modifiable = false
		vim.bo.readonly = true
	end)
end

vim.api.nvim_create_user_command("BqCompiled", function(cmdopts)
	show_compiled(cmdopts.line1, cmdopts.line2)
end, { range = "%" })

vim.keymap.set("n", "<leader>bp", "<cmd>BqCompiled<CR>", { desc = "BigQuery: preview compiled SQL" })
vim.keymap.set("x", "<leader>bp", ":BqCompiled<CR>", { desc = "BigQuery: preview compiled SQL (selection)" })

-- Live estimate: debounced dry-run on every edit, cached in b:bq_estimate for
-- the statusline. A failed dry-run (query invalid/incomplete mid-edit) just
-- hides the estimate rather than showing a stale or wrong one.
local debounce_timers = {}
-- bufnr -> true while a dbt compile / dry-run is in flight for it, so a
-- burst of edits can't pile up overlapping `dbt compile` processes (each
-- costs ~0.3-1.5s). The debounce timer already re-fires after every pause,
-- so skipping here just means the next pause's tick will pick up the result.
local resolving = {}

local function refresh_bq_estimate(bufnr)
	if not is_bigquery_target(bufnr) then
		vim.b[bufnr].bq_estimate = nil -- e.g. connection switched away from bigquery
		return
	end
	local sql = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	if vim.trim(sql) == "" then
		vim.b[bufnr].bq_estimate = nil
		vim.cmd.redrawstatus()
		return
	end
	if resolving[bufnr] then
		return
	end
	resolving[bufnr] = true
	resolve_sql(bufnr, sql, function(resolved)
		if not resolved then
			resolving[bufnr] = nil
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.b[bufnr].bq_estimate = nil
				vim.cmd.redrawstatus()
			end
			return
		end
		dry_run(resolved, vim.b[bufnr].db, function(bytes)
			resolving[bufnr] = nil
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			vim.b[bufnr].bq_estimate = bytes and human_bytes(bytes) or nil
			vim.cmd.redrawstatus()
		end)
	end)
end

local function schedule_bq_estimate(bufnr)
	local timer = debounce_timers[bufnr]
	if not timer then
		timer = vim.uv.new_timer()
		debounce_timers[bufnr] = timer
	end
	timer:stop()
	timer:start(600, 0, function()
		timer:stop()
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				refresh_bq_estimate(bufnr)
			end
		end)
	end)
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "sql", "mysql", "plsql" },
	group = vim.api.nvim_create_augroup("dadbod_completion", { clear = true }),
	callback = function(args)
		vim.bo.omnifunc = "vim_dadbod_completion#omni"
		vim.opt_local.complete:append("o")

		if dbt.project_root(args.buf) then
			-- dbt model files are never wire-executed on :w: they contain
			-- unresolved Jinja, and even resolved, a real run can be a
			-- mutating query (MERGE/INSERT for an incremental model) -- not
			-- something a routine save should trigger. vim-dadbod-ui attaches
			-- its own BufWritePost (execute_query) whenever this buffer gets
			-- a `b:db` via its UI (e.g. :DBUIFindBuffer); strip just that one
			-- autocmd before every write so a save always just saves. Use
			-- <leader>bR / :BqRun instead to deliberately run the
			-- dbt-compiled query.
			vim.api.nvim_create_autocmd("BufWritePre", {
				buffer = args.buf,
				callback = function()
					pcall(vim.api.nvim_clear_autocmds, { group = "db_ui_query", event = "BufWritePost", buffer = args.buf })
				end,
			})
		end

		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			buffer = args.buf,
			callback = function()
				schedule_bq_estimate(args.buf)
			end,
		})
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = args.buf,
			callback = function()
				local timer = debounce_timers[args.buf]
				if timer then
					timer:stop()
					timer:close()
					debounce_timers[args.buf] = nil
				end
				resolving[args.buf] = nil
			end,
		})
		schedule_bq_estimate(args.buf) -- also estimate on open, not just on edit
	end,
})

-- No-op outside sql/mysql/plsql buffers, so this is safe to append to
-- whatever the statusline already shows.
vim.o.statusline = vim.o.statusline
	.. "%{index(['sql','mysql','plsql'], &filetype) >= 0 && !empty(get(b:,'bq_estimate','')) ? '  BigQuery ~' . b:bq_estimate : ''}"

vim.keymap.set("n", "<leader>db", "<cmd>DBUIToggle<CR>", { desc = "Toggle DB UI (BigQuery)" })
vim.keymap.set("n", "<leader>bf", "<cmd>DBUIFindBuffer<CR>", { desc = "Find DB buffer" })
