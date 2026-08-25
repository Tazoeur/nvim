-- Resolves a dbt model's full Jinja (ref/source/config/var/custom macros,
-- {% if %} control flow -- everything) by asking dbt-fusion itself to
-- compile it: `dbt compile --inline "<sql>"` renders the SQL exactly as
-- dbt would, with no guessing. `--log-format json` makes it emit a
-- `CompiledNode` event with the rendered SQL in `data.compiled`, so no need
-- to locate/parse the `target/compiled/...` file it also writes.
--
-- This is slower than a cached ref/source lookup (dbt re-validates the
-- whole project graph per invocation: ~0.3-0.6s on a small project, ~1-1.5s
-- on this user's ~300-model project -- no meaningful speedup between
-- repeated calls was observed, since each run is a fresh process). Callers
-- debounce and guard against overlapping calls per buffer.
local M = {}

function M.project_root(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return nil
	end
	local found = vim.fs.find("dbt_project.yml", { path = vim.fn.fnamemodify(name, ":h"), upward = true })[1]
	return found and vim.fn.fnamemodify(found, ":h") or nil
end

-- callback(sql) on success, callback(nil, err) if dbt couldn't compile it.
-- `--project-dir`/`--profiles-dir` are passed explicitly (not just `cwd`):
-- dbt-fusion's default profiles-dir search is CWD + `~/.dbt`, not
-- project-dir, so a colocated profiles.yml (as in this user's projects)
-- would otherwise go unfound whenever the subprocess cwd isn't `root`.
function M.compile(sql, root, callback)
	vim.system({
		"dbt",
		"compile",
		"--inline",
		sql,
		"--project-dir",
		root,
		"--profiles-dir",
		root,
		"--log-format",
		"json",
		"--quiet",
	}, {
		cwd = root,
		text = true,
	}, function(res)
		vim.schedule(function()
			local errors = {}
			for line in (res.stdout or ""):gmatch("[^\n]+") do
				local ok, decoded = pcall(vim.json.decode, line)
				if ok and decoded.info then
					if decoded.info.name == "CompiledNode" and decoded.data then
						callback(decoded.data.compiled)
						return
					end
					if decoded.info.level == "error" and decoded.info.msg then
						table.insert(errors, decoded.info.msg)
					end
				end
			end
			if #errors > 0 then
				callback(nil, table.concat(errors, "\n"))
				return
			end
			callback(nil, res.stderr ~= "" and res.stderr or "dbt did not report a compiled node")
		end)
	end)
end

-- The "virtual SQL" for a dbt buffer: bufnr -> { raw, sql, err }, the most
-- recently compiled result for that buffer's exact current text. Kept
-- current by the caller's own debounced background compile (see
-- database.lua's live estimate) on every edit, so by the time a user asks
-- to run/preview the query, it's normally already sitting here -- compile_cached
-- only pays for an actual `dbt compile` when the text truly changed since
-- the last background refresh (e.g. right after opening a buffer, or if a
-- refresh is still in flight).
local cache = {}

-- Same contract as M.compile, but returns instantly from cache when `sql`
-- is byte-identical to the last resolve for this buffer.
function M.compile_cached(bufnr, sql, root, callback)
	local cached = cache[bufnr]
	if cached and cached.raw == sql then
		callback(cached.sql, cached.err)
		return
	end
	M.compile(sql, root, function(resolved, err)
		cache[bufnr] = { raw = sql, sql = resolved, err = err }
		callback(resolved, err)
	end)
end

-- Drop a buffer's cached compile so it doesn't linger after the buffer's
-- gone (call from BufDelete, alongside the debounce-timer cleanup).
function M.forget(bufnr)
	cache[bufnr] = nil
end

-- The BigQuery dataset a dbt model actually targets (its resolved `schema`),
-- so a buffer can be attached to a real, dataset-scoped connection
-- automatically instead of a project-only one -- table/column completion
-- needs a dataset to scope INFORMATION_SCHEMA to and returns nothing for a
-- project-only connection by design (see database.lua/is_bigquery_target).
--
-- Uses `dbt list --select path:<file>`, not `--inline` compile: an inline
-- compile has no identity of its own in the graph (unique_id:
-- sql_operation.inline_query, see M.compile above) and never reports a
-- destination -- only listing the model BY PATH surfaces its manifest
-- config (config.schema/config.database), the same resolution dbt itself
-- uses to build the real relation name.
--
-- callback(dataset, database_or_nil) on success -- database is nil when the
-- model doesn't override it, meaning the profile's own default project
-- applies. callback(nil) if dbt couldn't resolve it (e.g. a model with a
-- config error) -- silently, same as the rest of this module: no guessed
-- fallback.
function M.model_dataset(bufnr, root, callback)
	local abs = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p")
	local rel = abs:sub(#root + 2)
	vim.system({
		"dbt",
		"list",
		"--select",
		"path:" .. rel,
		"--output",
		"json",
		"--project-dir",
		root,
		"--profiles-dir",
		root,
		"--quiet",
	}, {
		cwd = root,
		text = true,
	}, function(res)
		vim.schedule(function()
			local first = (res.stdout or ""):match("[^\n]+")
			local ok, decoded = pcall(vim.json.decode, first or "")
			if not ok or not decoded.config or not decoded.config.schema or decoded.config.schema == "" then
				callback(nil)
				return
			end
			local database = decoded.config.database
			if database == vim.NIL then
				database = nil
			end
			callback(decoded.config.schema, database)
		end)
	end)
end

return M
