" Neovim's `:runtime {file}` (no bang) only sources the FIRST match on
" 'runtimepath' -- and our config directory precedes vim.pack's plugin dirs
" there. So shipping a file at this same path fully shadows vim-dadbod-ui's
" own autoload/db_ui/schemas.vim instead of complementing it: this file is a
" verbatim copy of it (every adapter's queries, results_parser, format_query,
" supports_schemes -- all unchanged), except db_ui#schemas#query, which now
" caches+backgrounds bigquery's two schema queries specifically (see below).
"
" Upstream: https://github.com/kristijanhusak/vim-dadbod-ui/blob/master/autoload/db_ui/schemas.vim
function! s:strip_quotes(results) abort
  return split(substitute(join(a:results),'"','','g'))
endfunction

function! s:results_parser(results, delimiter, min_len) abort
  if a:min_len ==? 1
    return filter(a:results, '!empty(trim(v:val))')
  endif
  let mapped = map(a:results, {_,row -> filter(split(row, a:delimiter), '!empty(trim(v:val))')})
  if a:min_len > 1
    return filter(mapped, 'len(v:val) ==? '.a:min_len)
  endif

  let counts = map(copy(mapped), 'len(v:val)')
  let min_len = max(counts)

  return filter(mapped,'len(v:val) ==? '.min_len)
endfunction

let s:postgres_foreign_key_query = "
      \ SELECT ccu.table_name AS foreign_table_name, ccu.column_name AS foreign_column_name, ccu.table_schema as foreign_table_schema
      \ FROM
      \     information_schema.table_constraints AS tc
      \     JOIN information_schema.key_column_usage AS kcu
      \       ON tc.constraint_name = kcu.constraint_name
      \     JOIN information_schema.constraint_column_usage AS ccu
      \       ON ccu.constraint_name = tc.constraint_name
      \ WHERE constraint_type = 'FOREIGN KEY' and kcu.column_name = '{col_name}' LIMIT 1"

let s:postgres_list_schema_query = "
    \ SELECT nspname as schema_name
    \ FROM pg_catalog.pg_namespace
    \ WHERE nspname !~ '^pg_temp_'
    \   and pg_catalog.has_schema_privilege(current_user, nspname, 'USAGE')
    \ order by nspname"

if empty(g:db_ui_use_postgres_views)
  let postgres_tables_and_views = "
        \ SELECT table_schema, table_name FROM information_schema.tables ;"
else
  let postgres_tables_and_views = "
        \ SELECT table_schema, table_name FROM information_schema.tables UNION ALL
        \ select schemaname, matviewname from pg_matviews;"
endif
let s:postgres_tables_and_views = postgres_tables_and_views

let s:postgresql = {
      \ 'args': ['-A', '-c'],
      \ 'foreign_key_query': s:postgres_foreign_key_query,
      \ 'schemes_query': s:postgres_list_schema_query,
      \ 'schemes_tables_query': s:postgres_tables_and_views,
      \ 'select_foreign_key_query': 'select * from "%s"."%s" where "%s" = %s',
      \ 'cell_line_number': 2,
      \ 'cell_line_pattern': '^-\++-\+',
      \ 'parse_results': {results,min_len -> s:results_parser(filter(results, '!empty(v:val)')[1:-2], '|', min_len)},
      \ 'default_scheme': 'public',
      \ 'layout_flag': '\\x',
      \ 'quote': 1,
      \ }

let s:sqlserver_foreign_keys_query = "
      \ SELECT TOP 1 c2.table_name as foreign_table_name, kcu2.column_name as foreign_column_name, kcu2.table_schema as foreign_table_schema
      \ from   information_schema.table_constraints c
      \        inner join information_schema.key_column_usage kcu
      \          on c.constraint_schema = kcu.constraint_schema and c.constraint_name = kcu.constraint_name
      \        inner join information_schema.referential_constraints rc
      \          on c.constraint_schema = rc.constraint_schema and c.constraint_name = rc.constraint_name
      \        inner join information_schema.table_constraints c2
      \          on rc.unique_constraint_schema = c2.constraint_schema and rc.unique_constraint_name = c2.constraint_name
      \        inner join information_schema.key_column_usage kcu2
      \          on c2.constraint_schema = kcu2.constraint_schema and c2.constraint_name = kcu2.constraint_name and kcu.ordinal_position = kcu2.ordinal_position
      \ where  c.constraint_type = 'FOREIGN KEY'
      \ and kcu.column_name = '{col_name}'
      \ "

let s:sqlserver = {
      \   'args': ['-h-1', '-W', '-s', '|', '-Q'],
      \   'foreign_key_query': trim(s:sqlserver_foreign_keys_query),
      \   'schemes_query': 'SELECT schema_name FROM INFORMATION_SCHEMA.SCHEMATA',
      \   'schemes_tables_query': 'SELECT table_schema, table_name FROM INFORMATION_SCHEMA.TABLES',
      \   'select_foreign_key_query': 'select * from %s.%s where %s = %s',
      \   'cell_line_number': 2,
      \   'cell_line_pattern': '^-\+.-\+',
      \   'parse_results': {results, min_len -> s:results_parser(results[0:-3], '|', min_len)},
      \   'quote': 0,
      \   'default_scheme': 'dbo',
      \ }

let s:mysql_foreign_key_query =  "
      \ SELECT referenced_table_name, referenced_column_name, referenced_table_schema
      \ from information_schema.key_column_usage
      \ where referenced_table_name is not null and column_name = '{col_name}' LIMIT 1"
let s:mysql = {
      \ 'foreign_key_query': s:mysql_foreign_key_query,
      \ 'schemes_query': 'SELECT schema_name FROM information_schema.schemata',
      \ 'schemes_tables_query': 'SELECT table_schema, table_name FROM information_schema.tables',
      \ 'select_foreign_key_query': 'select * from %s.%s where %s = %s',
      \ 'cell_line_number': 3,
      \ 'requires_stdin': v:true,
      \ 'cell_line_pattern': '^+-\++-\+',
      \ 'parse_results': {results, min_len -> s:results_parser(results[1:], '\t', min_len)},
      \ 'default_scheme': '',
      \ 'layout_flag': '\\G',
      \ 'quote': 0,
      \ 'filetype': 'mysql',
      \ }

let s:oracle_args = join(
      \    [
           \  'SET linesize 4000',
           \  'SET pagesize 4000',
           \  'COLUMN owner FORMAT a20',
           \  'COLUMN table_name FORMAT a25',
           \  'COLUMN column_name FORMAT a25',
           \  '%s',
      \    ],
      \    ";\n"
      \ ).';'

function! s:get_oracle_queries()
  let common_condition = ""

  if !g:db_ui_is_oracle_legacy
    let common_condition = "AND U.common = 'NO'"
  endif

  let foreign_key_query = "
      \SELECT /*csv*/ DISTINCT RFRD.table_name, RFRD.column_name, RFRD.owner
      \ FROM all_cons_columns RFRD
      \ JOIN all_constraints CON ON RFRD.constraint_name = CON.r_constraint_name
      \ JOIN all_cons_columns RFRING ON CON.constraint_name = RFRING.constraint_name
      \ JOIN all_users U ON CON.owner = U.username
      \ WHERE CON.constraint_type = 'R'
      \ " . common_condition . "
      \ AND RFRING.column_name = '{col_name}'"

  let schemes_query = "
      \SELECT /*csv*/ username
      \ FROM all_users U
      \ WHERE 1 = 1
      \ " . common_condition . "
      \ ORDER BY username"

  let schemes_tables_query = "
      \SELECT /*csv*/ T.owner, T.table_name
      \ FROM (
      \ SELECT owner, table_name
      \ FROM all_tables
      \ UNION SELECT owner, view_name AS \"table_name\"
      \ FROM all_views
      \ ) T
      \ JOIN all_users U ON T.owner = U.username
      \ WHERE 1 = 1
      \ " . common_condition . "
      \ ORDER BY T.table_name"

  return {
      \ 'foreign_key_query': printf(s:oracle_args, foreign_key_query),
      \ 'schemes_query': printf(s:oracle_args, schemes_query),
      \ 'schemes_tables_query': printf(s:oracle_args, schemes_tables_query),
      \ }
endfunction

let oracle_queries = s:get_oracle_queries()

let s:oracle = {
      \   'callable': 'filter',
      \   'cell_line_number': 1,
      \   'cell_line_pattern': '^-\+\( \+-\+\)*',
      \   'default_scheme': '',
      \   'foreign_key_query': oracle_queries.foreign_key_query,
      \   'has_virtual_results': v:true,
      \   'parse_results': {results, min_len -> s:results_parser(results[3:], '\s\s\+', min_len)},
      \   'parse_virtual_results': {results, min_len -> s:results_parser(results[3:], '\s\s\+', min_len)},
      \   'requires_stdin': v:true,
      \   'quote': v:true,
      \   'schemes_query': oracle_queries.schemes_query,
      \   'schemes_tables_query': oracle_queries.schemes_tables_query,
      \   'select_foreign_key_query': printf(s:oracle_args, 'SELECT /*csv*/ * FROM "%s"."%s" WHERE "%s" = %s'),
      \   'filetype': 'plsql',
      \ }

if index(['sql', 'sqlcl'], get(g:, 'dbext_default_ORA_bin', '')) >= 0
  let s:oracle.parse_results = {results, min_len -> s:results_parser(s:strip_quotes(results[3:]), ',', min_len)}
  let s:oracle.parse_virtual_results = {results, min_len -> s:results_parser(s:strip_quotes(results[3:]), ',', min_len)}
endif

" Not part of upstream: g:db_adapter_bigquery_region, when set, forces every
" bigquery project to be queried as that one region (skips the discovery
" below -- useful as a manual override / to skip the extra `bq ls` round
" trip if you already know it). Left unset (the default), the region(s) a
" given project's datasets actually live in are discovered per-project (see
" s:fetch_bigquery_regions) rather than assumed -- a project's datasets can
" span more than one region, and region-qualified INFORMATION_SCHEMA views
" only ever see one region at a time, so a single global default (upstream:
" 'region-us') silently misses every dataset outside it.
if !exists('g:db_adapter_bigquery_region')
  let g:db_adapter_bigquery_region = ''
endif

" Sentinels, not real SQL: s:bigquery_query (below) recognizes which of the
" two it was asked for and builds the actual per-region UNION ALL query once
" that project's regions are known.
let s:bigquery_schemas_query = '@bigquery:schemas'
let s:bigquery_schema_tables_query = '@bigquery:schema_tables'

let s:db_adapter_bigquery_max_results = 100000
let s:bigquery = {
      \ 'callable': 'filter',
      \ 'args': ['--format=csv', '--max_rows=' .. s:db_adapter_bigquery_max_results],
      \ 'schemes_query': s:bigquery_schemas_query,
      \ 'schemes_tables_query': s:bigquery_schema_tables_query,
      \ 'parse_results': {results, min_len -> s:results_parser(results[1:], ',', min_len)},
      \ 'layout_flag': '\\x',
      \ 'requires_stdin': v:true,
      \ }


let s:clickhouse_schemes_query = "
      \ SELECT name as schema_name
      \ FROM system.databases
      \ ORDER BY name"

let s:clickhouse_schemes_tables_query = "
      \ SELECT database AS table_schema, name AS table_name
      \ FROM system.tables
      \ ORDER BY table_name"

let s:clickhouse = {
      \ 'args': ['-q'],
      \ 'schemes_query': trim(s:clickhouse_schemes_query),
      \ 'schemes_tables_query': trim(s:clickhouse_schemes_tables_query),
      \ 'cell_line_number': 1,
      \ 'cell_line_pattern': '^.*$',
      \ 'parse_results': {results, min_len -> s:results_parser(results, '\t', min_len)},
      \ 'default_scheme': '',
      \ 'quote': 1,
      \ }

" Add ClickHouse to the schemas dictionary
let s:schemas = {
      \ 'postgres': s:postgresql,
      \ 'postgresql': s:postgresql,
      \ 'sqlserver': s:sqlserver,
      \ 'mysql': s:mysql,
      \ 'mariadb': s:mysql,
      \ 'oracle': s:oracle,
      \ 'bigquery': s:bigquery,
      \ 'clickhouse': s:clickhouse,
      \ }


if !exists('g:db_adapter_postgres')
  let g:db_adapter_postgres = 'db#adapter#postgresql#'
endif

if !exists('g:db_adapter_sqlite3')
  let g:db_adapter_sqlite3 = 'db#adapter#sqlite#'
endif

function! db_ui#schemas#get(scheme) abort
  return get(s:schemas, a:scheme, {})
endfunction

function! s:format_query(db, scheme, query) abort
  let conn = type(a:db) == v:t_string ? a:db : a:db.conn
  let callable = get(a:scheme, 'callable', 'interactive')
  let cmd = db#adapter#dispatch(conn, callable) + get(a:scheme, 'args', [])
  if get(a:scheme, 'requires_stdin', v:false)
    return [cmd, a:query]
  endif
  return [cmd + [a:query], '']
endfunction

" Not part of upstream: db_ui#schemas#query is called SYNCHRONOUSLY by
" drawer.vim's populate_schemas every time a bigquery connection/dataset
" node is expanded, with no async path of its own. A cold `bq` call here
" (schemas_query, then schemes_tables_query -- TWO of them, back to back)
" can take several seconds, freezing all of Neovim meanwhile. Same fix as
" db#adapter#bigquery#tables() in autoload/db/adapter/bigquery.vim: return
" whatever's cached right now (empty on the very first call for this
" connection+query), and fetch in the background, refreshing the drawer
" once the real rows land. Every other adapter (postgres, mysql, sqlserver,
" oracle, clickhouse) is untouched -- none of them were reported as slow.
let s:bigquery_cache = {}
let s:bigquery_jobs = {}

function! db_ui#schemas#query(db, scheme, query) abort
  if a:scheme is s:bigquery
    return s:bigquery_query(a:db, a:query)
  endif
  let result = call('db#systemlist', s:format_query(a:db, a:scheme, a:query))
  return map(result, {_, val -> substitute(val, "\r$", "", "")})
endfunction

" Clears every cached bigquery schema/table-list result -- e.g. after
" creating a dataset/table (or a dataset in a brand new region) that should
" now show up in the drawer without restarting Neovim.
function! db_ui#schemas#bigquery_refresh() abort
  let s:bigquery_cache = {}
  let s:bigquery_regions_cache = {}
endfunction

function! s:bigquery_conn(db) abort
  return type(a:db) == v:t_string ? a:db : a:db.conn
endfunction

" bigquery://project (no dataset, no extra colon) parses as a normal
" host-form URL (.host); bigquery://project:dataset has a second colon that
" breaks db#url#parse's host:port pattern, so it falls back to opaque
" (//project:dataset) instead -- same two shapes db#adapter#bigquery's own
" command_for_url distinguishes, handled here since this file doesn't share
" its script-locals.
function! s:bigquery_project(conn) abort
  let parsed = db#url#parse(a:conn)
  if !empty(get(parsed, 'host', ''))
    return parsed.host
  endif
  let host_targets = split(substitute(get(parsed, 'opaque', ''), '/', '', 'g'), ':')
  return get(host_targets, 0, '')
endfunction

" Cached per project (region-tagged INFORMATION_SCHEMA views don't care
" which dataset a given connection defaults to), not per connection --
" multiple bigquery:// connections against the same project share one
" discovery and one schema/table fetch.
let s:bigquery_regions_cache = {}
let s:bigquery_regions_jobs = {}
" project -> a connection string to retry s:bigquery_query with once that
" project's regions land (whichever connection first asked).
let s:bigquery_regions_conn = {}

function! s:bigquery_regions(project) abort
  if !empty(g:db_adapter_bigquery_region)
    return [g:db_adapter_bigquery_region]
  endif
  return get(s:bigquery_regions_cache, a:project, [])
endfunction

function! s:bigquery_query(db, query) abort
  let conn = s:bigquery_conn(a:db)
  let project = s:bigquery_project(conn)
  let key = project . "\x00" . a:query
  if has_key(s:bigquery_cache, key) || has_key(s:bigquery_jobs, key)
    return get(s:bigquery_cache, key, [])
  endif

  let regions = s:bigquery_regions(project)
  if empty(regions)
    let s:bigquery_regions_conn[project] = conn
    if !has_key(s:bigquery_regions_jobs, project) && !has_key(s:bigquery_regions_cache, project)
      call s:fetch_bigquery_regions(project)
    endif
    return []
  endif

  call s:bigquery_fetch(conn, a:query, regions, key)
  return []
endfunction

" Datasets.list ('bq ls'), not INFORMATION_SCHEMA: needs only a light
" per-dataset 'get'-level permission (unlike the project-wide
" tables/routines 'list' the schema/table scan itself needs), and its JSON
" output already reports each dataset's location directly -- one call
" discovers every region a project's datasets live in.
function! s:fetch_bigquery_regions(project) abort
  let cmd = ['bq'] + (empty(a:project) ? [] : ['--project_id='.a:project]) + ['--format=json', 'ls']
  let lines = ['']
  let job = jobstart(cmd, {
        \ 'on_stdout': function('s:job_collect', [lines]),
        \ 'on_stderr': function('s:job_collect', [lines]),
        \ 'on_exit': function('s:bigquery_regions_done', [a:project, lines]),
        \ })
  if job <= 0
    return
  endif
  let s:bigquery_regions_jobs[a:project] = job
  call chanclose(job, 'stdin')
endfunction

function! s:bigquery_regions_done(project, lines, job_id, status, event) abort
  call remove(s:bigquery_regions_jobs, a:project)
  if a:status != 0
    return
  endif
  try
    let datasets = json_decode(join(a:lines, ''))
  catch
    return
  endtry
  if type(datasets) != v:t_list
    return
  endif

  let regions = {}
  for ds in datasets
    let loc = tolower(get(ds, 'location', ''))
    if !empty(loc)
      let regions['region-'.loc] = 1
    endif
  endfor
  if empty(regions)
    return
  endif
  let s:bigquery_regions_cache[a:project] = sort(keys(regions))

  " Regions just landed: retry both listing kinds now that we know where to
  " look. Each retry either serves from its own cache or kicks off (and
  " re-renders after) its own fetch -- same path as the first ever call.
  let conn = get(s:bigquery_regions_conn, a:project, '')
  if empty(conn)
    return
  endif
  call s:bigquery_query(conn, s:bigquery_schemas_query)
  call s:bigquery_query(conn, s:bigquery_schema_tables_query)
endfunction

function! s:bigquery_region_query(query, region) abort
  if a:query ==# s:bigquery_schemas_query
    return printf('SELECT schema_name FROM `%s`.INFORMATION_SCHEMA.SCHEMATA', a:region)
  endif
  return printf('SELECT table_schema, table_name FROM `%s`.INFORMATION_SCHEMA.TABLES', a:region)
endfunction

function! s:bigquery_fetch(conn, query, regions, key) abort
  let sql = join(map(copy(a:regions), {_, r -> s:bigquery_region_query(a:query, r)}), "\nUNION ALL\n")
  let [cmd, stdin] = s:format_query(a:conn, s:bigquery, sql)
  let lines = ['']
  let job = jobstart(cmd, {
        \ 'on_stdout': function('s:job_collect', [lines]),
        \ 'on_stderr': function('s:job_collect', [lines]),
        \ 'on_exit': function('s:bigquery_done', [a:key, lines]),
        \ })
  if job <= 0
    return
  endif
  let s:bigquery_jobs[a:key] = job
  if !empty(stdin)
    call chansend(job, stdin)
  endif
  call chanclose(job, 'stdin')
endfunction

function! s:job_collect(lines, job_id, data, event) abort
  let a:lines[-1] .= a:data[0]
  call extend(a:lines, a:data[1:])
endfunction

function! s:bigquery_done(key, lines, job_id, status, event) abort
  call remove(s:bigquery_jobs, a:key)
  if a:status != 0
    return
  endif
  let lines = a:lines
  if !empty(lines) && empty(lines[-1])
    call remove(lines, -1)
  endif
  let s:bigquery_cache[a:key] = map(lines, {_, val -> substitute(val, "\r$", "", "")})
  " A plain render() only redraws whatever's already in the drawer's own
  " per-connection state -- it does NOT re-run populate_schemas/
  " populate_tables, so it would just redraw the same stale "Schemas (0)"
  " forever even though s:bigquery_cache (read on the NEXT populate_schemas
  " call, above) now has the real data. {'dbs': 1} makes it actually
  " re-populate every configured connection first (cheap: unchanged
  " connections keep their live .conn and just re-run populate(), same as
  " manually reopening the drawer).
  if exists('*db_ui#drawer#get') && db_ui#drawer#get().is_opened()
    call db_ui#drawer#get().render({'dbs': 1})
  endif
endfunction

function db_ui#schemas#supports_schemes(scheme, parsed_url)
  let schema_support = !empty(get(a:scheme, 'schemes_query', 0))
  if empty(schema_support)
    return 0
  endif
  let scheme_name = tolower(get(a:parsed_url, 'scheme', ''))
  " Mysql and MariaDB should not show schemas if the path (database name) is
  " defined
  if (scheme_name ==? 'mysql' || scheme_name ==? 'mariadb') && a:parsed_url.path !=? '/'
    return 0
  endif

  return 1
endfunction
