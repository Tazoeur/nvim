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

-- autoload/db_ui/schemas.vim's bigquery dataset-tree browsing auto-discovers
-- each project's dataset region(s) via `bq ls` rather than assuming one
-- (our datasets live in europe-west1, not upstream's 'region-us' default) --
-- see g:db_adapter_bigquery_region there for the manual-override escape
-- hatch, left unset here so discovery runs.
--
-- autoload/vim_dadbod_completion/schemas.vim's schema-name completion (e.g.
-- `FROM dashboard_<Tab>` on a project-only connection) can't do that same
-- per-project auto-discovery -- its query is a fixed string with no room to
-- inject a per-connection value -- so it needs this set explicitly. Every
-- dataset sampled in this project is europe-west1; if a dataset in a
-- different region gets added later it just won't show up in THIS specific
-- completion (the drawer's own dataset-tree browsing is unaffected, since
-- that one auto-discovers per project).
vim.g.vim_dadbod_completion_bigquery_region = "region-europe-west1"

-- One connection per line. Project-only connections need fully-qualified
-- table names in queries (`project.dataset.table`); add ':dataset' to a
-- connection to get a default dataset (and table-name completion for it).
vim.g.dbs = {
	{ name = "bigquery-happyhoursmarketdev", url = "bigquery://happyhoursmarketdev" },
}

local dbt = require("dbt")
local bq_schema = require("bq_schema")

-- Resolves dbt Jinja (see lua/dbt.lua) when `bufnr` is a dbt model, via
-- `dbt compile`; calls back with the SQL unchanged for a plain .sql file.
-- callback(sql) on success, callback(nil, err) if dbt couldn't compile it.
-- Goes through dbt's per-buffer cache (M.compile_cached): the background
-- live-estimate refresh (below) keeps that cache current as the buffer is
-- edited, so this is usually an instant hit rather than a fresh ~0.3-1.5s
-- `dbt compile` -- the "virtual SQL for this buffer" is normally already
-- sitting there by the time BqRun/BqCompiled/BqDryRun ask for it.
local function resolve_sql(bufnr, sql, callback)
	-- Resolve 0 ("current buffer") to a real number: the cache is a plain
	-- Lua table keyed by bufnr, and the live-refresh path below always
	-- caches under the real number (from a FileType/TextChanged autocmd's
	-- args.buf) -- caching under the literal 0 here would never hit it.
	if bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	local root = dbt.project_root(bufnr)
	if not root then
		callback(sql)
		return
	end
	dbt.compile_cached(bufnr, sql, root, callback)
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

-- true for an unscoped `bigquery://project` connection (no dataset) -- the
-- one vim.g.dbs actually has, which table/column completion never returns
-- anything for (needs a dataset to scope INFORMATION_SCHEMA to).
local function is_project_only_bigquery(url)
	return url ~= nil and url:match("^bigquery://[^:/]*$") ~= nil
end

-- The bigquery:// project configured in vim.g.dbs, reused as the default
-- project wherever one isn't otherwise known (an auto-attached dataset
-- connection, a bare `dataset.table` reference with no project prefix)
-- instead of a separate, easily-drifting config value.
local function default_bigquery_project()
	for _, db in ipairs(vim.g.dbs or {}) do
		local project = db.url and db.url:match("^bigquery://([^:/]*)")
		if project and project ~= "" then
			return project
		end
	end
	return nil
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

-- BqCompiled's preview: one buffer per source file, named "virtual SQL for
-- {source_path}" -- this *is* that buffer's dbt-compiled virtual SQL, just
-- materialized read-only now that the user asked to see it. Successive
-- previews of the same file reuse that same buffer/window (jumping to it if
-- it's already open, splitting it back in if it got closed) and just
-- refresh its contents, rather than piling up a new window each time.
local function show_virtual_sql(text, source_path)
	local name = "virtual SQL for " .. (source_path ~= "" and source_path or "[No Name]")
	local bufnr = vim.fn.bufnr(name)

	if bufnr == -1 then
		vim.cmd("vertical rightbelow new")
		vim.bo.buftype = "nofile"
		vim.bo.bufhidden = "wipe"
		vim.bo.swapfile = false
		vim.bo.filetype = "sql"
		vim.api.nvim_buf_set_name(0, name)
		bufnr = vim.api.nvim_get_current_buf()
	else
		local winid = vim.fn.bufwinid(bufnr)
		if winid ~= -1 then
			vim.api.nvim_set_current_win(winid)
		else
			vim.cmd("vertical rightbelow sbuffer " .. bufnr)
		end
	end

	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].readonly = false
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n"))
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].readonly = true
end

-- Deliberately RUNS the query for real (not a dry-run): resolves dbt Jinja
-- if applicable, then executes via vim-dadbod's own :DB, so results land in
-- the usual dbout preview split. The resolved SQL is handed to :DB via its
-- documented `:DB [url] < {file}` form (a plain temp file, never a buffer)
-- specifically so :DB never needs the query to be the current buffer --
-- nothing about running a query opens or shows a window here; the source
-- buffer/window stays exactly as the user left it, and only the results
-- preview split appears.
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
		local tmpfile = vim.fn.tempname() .. ".sql"
		vim.fn.writefile(vim.split(resolved, "\n"), tmpfile)
		vim.cmd("DB " .. db_url .. " < " .. vim.fn.fnameescape(tmpfile))
	end)
end

vim.api.nvim_create_user_command("BqRun", function(cmdopts)
	run_query(cmdopts.line1, cmdopts.line2)
end, { range = "%" })

vim.keymap.set("n", "<leader>br", "<cmd>BqRun<CR>", { desc = "BigQuery: run query for real" })
vim.keymap.set("x", "<leader>br", ":BqRun<CR>", { desc = "BigQuery: run query for real (selection)" })

-- Just shows the SQL dbt would actually run (ref/source/config/macros
-- resolved), read-only, without running anything -- no bq/connection
-- involved at all.
local function show_compiled(line1, line2)
	local source_path = vim.api.nvim_buf_get_name(0)
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
		show_virtual_sql(resolved, source_path)
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
		-- Warm column metadata (name/type/description) for whatever
		-- dataset(s) this RESOLVED query actually touches -- scanning the
		-- resolved SQL rather than the raw buffer text so a dbt file's
		-- {{ ref()/source() }} calls are covered once dbt has turned them
		-- into real `dataset.table` references, not missed because the
		-- literal Jinja text never contains a dataset name.
		local project = (vim.b[bufnr].db and vim.b[bufnr].db:match("^bigquery://([^:/]*)")) or default_bigquery_project()
		if project then
			bq_schema.scan_and_ensure(resolved, project)
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

-- Attaches a dbt model buffer to its own dataset-scoped bigquery connection,
-- derived from dbt's own resolved schema for THIS model (see
-- dbt.model_dataset), instead of leaving it on vim.g.dbs's project-only
-- entry. Only touches b:db when it's unset or already project-only bigquery
-- -- never clobbers a connection the user (or DBUI) explicitly scoped or
-- picked themselves, bigquery or otherwise.
local function auto_attach_dataset(bufnr, root)
	local current = vim.b[bufnr].db
	if current ~= nil and current ~= "" and not is_project_only_bigquery(current) then
		return
	end
	dbt.model_dataset(bufnr, root, function(dataset, database)
		if not dataset or not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		-- b:db may have been set (by the user, or DBUI) while dbt was running.
		local again = vim.b[bufnr].db
		if again ~= nil and again ~= "" and not is_project_only_bigquery(again) then
			return
		end
		local project = database or (again and again:match("^bigquery://([^:/]*)")) or default_bigquery_project()
		if not project then
			return
		end
		vim.b[bufnr].db = ("bigquery://%s:%s"):format(project, dataset)
	end)
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "sql", "mysql", "plsql" },
	group = vim.api.nvim_create_augroup("dadbod_completion", { clear = true }),
	callback = function(args)
		vim.bo.omnifunc = "vim_dadbod_completion#omni"
		vim.opt_local.complete:append("o")

		local dbt_root = dbt.project_root(args.buf)
		if dbt_root then
			auto_attach_dataset(args.buf, dbt_root)
			-- dbt model files are never wire-executed on :w: they contain
			-- unresolved Jinja, and even resolved, a real run can be a
			-- mutating query (MERGE/INSERT for an incremental model) -- not
			-- something a routine save should trigger. vim-dadbod-ui attaches
			-- its own BufWritePost (execute_query) whenever this buffer gets
			-- a `b:db` via its UI (e.g. :DBUIFindBuffer); strip just that one
			-- autocmd before every write so a save always just saves. Use
			-- <leader>br / :BqRun instead to deliberately run the
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
				dbt.forget(args.buf)
			end,
		})
		schedule_bq_estimate(args.buf) -- also estimate on open, not just on edit
	end,
})

-- No-op outside sql/mysql/plsql buffers, so this is safe to append to
-- whatever the statusline already shows.
vim.o.statusline = vim.o.statusline
	.. "%{index(['sql','mysql','plsql'], &filetype) >= 0 && !empty(get(b:,'bq_estimate','')) ? '  BigQuery ~' . b:bq_estimate : ''}"

vim.keymap.set("n", "<leader>ub", "<cmd>DBUIToggle<CR>", { desc = "Toggle DB UI (BigQuery)" })
vim.keymap.set("n", "<leader>bf", "<cmd>DBUIFindBuffer<CR>", { desc = "Find DB buffer" })

-- Table/schema lists in the drawer are cached in-session (see
-- db#adapter#bigquery#tables in autoload/db/adapter/bigquery.vim and
-- db_ui#schemas#query in autoload/db_ui/schemas.vim) so expanding a
-- connection never blocks on `bq`. This drops and re-fetches every
-- configured BigQuery connection's cache -- for when a dataset/table was
-- just created/dropped and should show up without restarting Neovim.
vim.api.nvim_create_user_command("BqRefreshTables", function()
	vim.fn["db_ui#schemas#bigquery_refresh"]()
	for _, db in ipairs(vim.g.dbs or {}) do
		if db.url and db.url:match("^bigquery:") then
			vim.fn["db#adapter#bigquery#refresh_tables"](db.url)
		end
	end
end, {})
