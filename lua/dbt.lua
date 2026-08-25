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
function M.compile(sql, root, callback)
	vim.system({ "dbt", "compile", "--inline", sql, "--log-format", "json", "--quiet" }, {
		cwd = root,
		text = true,
	}, function(res)
		vim.schedule(function()
			for line in (res.stdout or ""):gmatch("[^\n]+") do
				local ok, decoded = pcall(vim.json.decode, line)
				if ok and decoded.info and decoded.info.name == "CompiledNode" and decoded.data then
					callback(decoded.data.compiled)
					return
				end
			end
			callback(nil, res.stderr ~= "" and res.stderr or "dbt did not report a compiled node")
		end)
	end)
end

return M
