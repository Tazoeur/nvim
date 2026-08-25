-- Lazily fetches column metadata (name, type, description) for every table
-- in a BigQuery dataset -- one query per dataset via
-- INFORMATION_SCHEMA.COLUMN_FIELD_PATHS (INFORMATION_SCHEMA.COLUMNS has no
-- description field; COLUMN_FIELD_PATHS has both data_type and description
-- in one place), not one query per table.
--
-- Two triggers ask for a dataset (see M.ensure below): expanding a schema
-- node in the DBUI drawer (ftplugin/dbui.vim) and editing a SQL/dbt buffer
-- whose resolved query references `dataset.table` in a FROM/JOIN
-- (database.lua, on the same debounced refresh as the live cost estimate --
-- scanning the *resolved* SQL, not the raw buffer text, so a dbt file's
-- {{ ref()/source() }} calls are covered once dbt has resolved them, not
-- missed because the literal Jinja text never contains a dataset name).
--
-- Consumed by lua/vim_dadbod_completion/blink.lua (a shadow of the plugin's
-- own blink source) to attach type/description to column completion items.
local M = {}

-- dataset -> { [table_name] = { [column_name] = {type=.., description=..} } }
local cache = {}
local in_flight = {}

-- nil if the dataset hasn't been fetched yet, or the table/column isn't in
-- it (e.g. a column-less/quota-limited edge case) -- callers just skip
-- enrichment rather than showing a guessed/blank value.
function M.get(dataset, table, column)
	local by_table = cache[dataset]
	local by_column = by_table and by_table[table]
	return by_column and by_column[column]
end

-- Extracts every "project.dataset"/"dataset" (bare, using default_project)
-- referenced after a FROM or JOIN in `sql`, quoted or not, and calls
-- M.ensure for each. Safe to call on arbitrary/partial SQL: an identifier
-- chain that isn't actually a real dataset just fails its bq query quietly
-- later, same as everywhere else in this config -- no guessing about
-- whether a match is "real" ahead of time.
function M.scan_and_ensure(sql, default_project)
	local seen = {}
	local function handle(clause)
		clause = clause:gsub("`", "")
		local parts = {}
		for p in clause:gmatch("[^.]+") do
			table.insert(parts, p)
		end
		local project, dataset
		if #parts == 3 then
			project, dataset = parts[1], parts[2]
		elseif #parts == 2 and default_project then
			project, dataset = default_project, parts[1]
		end
		if project and dataset and not seen[project .. ":" .. dataset] then
			seen[project .. ":" .. dataset] = true
			M.ensure(project, dataset)
		end
	end
	for clause in sql:gmatch("[Ff][Rr][Oo][Mm]%s+([%w_`.]+)") do
		handle(clause)
	end
	for clause in sql:gmatch("[Jj][Oo][Ii][Nn]%s+([%w_`.]+)") do
		handle(clause)
	end
end

-- No-op once cached or already in flight for this dataset.
function M.ensure(project, dataset)
	if cache[dataset] or in_flight[dataset] then
		return
	end
	in_flight[dataset] = true
	local sql = ("SELECT table_name, column_name, data_type, description FROM `%s`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS"):format(
		dataset
	)
	vim.system({
		"bq",
		"--project_id=" .. project,
		"query",
		"--format=json",
		"--nouse_legacy_sql",
	}, { stdin = sql, text = true }, function(res)
		vim.schedule(function()
			in_flight[dataset] = nil
			if res.code ~= 0 then
				return
			end
			local ok, rows = pcall(vim.json.decode, res.stdout or "")
			if not ok or type(rows) ~= "table" then
				return
			end
			local by_table = {}
			for _, row in ipairs(rows) do
				if row.table_name and row.column_name then
					by_table[row.table_name] = by_table[row.table_name] or {}
					by_table[row.table_name][row.column_name] = {
						type = row.data_type,
						description = (row.description and row.description ~= vim.NIL and row.description ~= "")
								and row.description
							or nil,
					}
				end
			end
			cache[dataset] = by_table
		end)
	end)
end

-- Drops a dataset's cached metadata and refetches it -- e.g. after a column
-- was added/renamed/documented and should show up without restarting.
function M.refresh(project, dataset)
	cache[dataset] = nil
	M.ensure(project, dataset)
end

return M
