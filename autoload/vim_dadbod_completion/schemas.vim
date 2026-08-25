" Neovim's `:runtime {file}` (no bang) only sources the FIRST match on
" 'runtimepath' -- and our config directory precedes vim.pack's plugin dirs
" there. So shipping a file at this same path fully shadows
" vim-dadbod-completion's own autoload/vim_dadbod_completion/schemas.vim
" instead of complementing it: this file is a verbatim copy of it (every
" other backend's queries/parsers -- postgres, oracle, mysql, sqlite,
" sqlserver, clickhouse -- unchanged), plus a 'bigquery' entry (which
" upstream doesn't provide) for column/field completion.
"
" Upstream: https://github.com/kristijanhusak/vim-dadbod-completion/blob/master/autoload/vim_dadbod_completion/schemas.vim
let s:base_column_query = 'SELECT TABLE_NAME,COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS'
let s:query = s:base_column_query.' ORDER BY COLUMN_NAME ASC'
let s:schema_query = 'SELECT TABLE_SCHEMA,TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS GROUP BY TABLE_SCHEMA,TABLE_NAME'
let s:count_query = 'SELECT COUNT(*) AS total FROM INFORMATION_SCHEMA.COLUMNS'
let s:table_column_query = s:base_column_query.' WHERE TABLE_NAME={db_tbl_name}'
let s:reserved_words = vim_dadbod_completion#reserved_keywords#get_as_dict()
let s:quote_rules = {
      \ 'camelcase': {val -> val =~# '[A-Z]' && val =~# '[a-z]'},
      \ 'space': {val -> val =~# '\s'},
      \ 'reserved_word': {val -> has_key(s:reserved_words, toupper(val))}
      \ }

if get(g:, 'vim_dadbod_completion_lowercase_keywords', 0) == 1
  let s:quote_rules['reserved_word'] = {val -> has_key(s:reserved_words, tolower(val))}
endif

function! s:map_and_filter(delimiter, list) abort
  return filter(
        \ map(a:list, { _, table -> map(split(table, a:delimiter), 'trim(v:val)') }),
        \ 'len(v:val) ==? 2'
        \ )
endfunction

function! s:should_quote(rules, val) abort
  if empty(trim(a:val))
    return 0
  endif

  let do_quote = 0

  for rule in a:rules
    let do_quote = s:quote_rules[rule](a:val)
    if do_quote
      break
    endif
  endfor

  return do_quote
endfunction

function! s:count_parser(index, result) abort
  return str2nr(get(a:result, a:index, 0))
endfunction

let s:postgres = {
      \ 'args': ['-A', '-c'],
      \ 'column_query': s:query,
      \ 'count_column_query': s:count_query,
      \ 'table_column_query': {table -> substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", '')},
      \ 'functions_query': "SELECT DISTINCT(routine_name) FROM information_schema.routines WHERE routine_type='FUNCTION'",
      \ 'functions_parser': {list->list[1:-4]},
      \ 'schemas_query': s:schema_query,
      \ 'schemas_parser': function('s:map_and_filter', ['|']),
      \ 'quote': ['"', '"'],
      \ 'should_quote': function('s:should_quote', [['camelcase', 'reserved_word', 'space']]),
      \ 'column_parser': function('s:map_and_filter', ['|']),
      \ 'count_parser': function('s:count_parser', [1])
      \ }

let s:oracle_args = "echo \"SET linesize 4000;\nSET pagesize 4000;\n%s\" | "
let s:oracle_base_column_query = printf(s:oracle_args, "COLUMN column_name FORMAT a50;\nCOLUMN table_name FORMAT a50;\nSELECT C.table_name, C.column_name FROM all_tab_columns C JOIN all_users U ON C.owner = U.username WHERE U.common = 'NO' %s;")
let s:oracle = {
\   'column_parser': function('s:map_and_filter', ['\s\s\+']),
\   'column_query': printf(s:oracle_base_column_query, 'ORDER BY C.column_name ASC'),
\   'count_column_query': printf(s:oracle_args, "COLUMN total FORMAT 9999999;\nSELECT COUNT(*) AS total FROM all_tab_columns C JOIN all_users U ON C.owner = U.username WHERE U.common = 'NO';"),
\   'count_parser': function('s:count_parser', [1]),
\   'quote': ['"', '"'],
\   'requires_stdin': v:true,
\   'schemas_query': printf(s:oracle_args, "COLUMN owner FORMAT a20;\nCOLUMN table_name FORMAT a25;\nSELECT T.owner, T.table_name FROM all_tables T JOIN all_users U ON T.owner = U.username WHERE U.common = 'NO' ORDER BY T.table_name;"),
\   'schemas_parser': function('s:map_and_filter', ['\s\s\+']),
\   'should_quote': function('s:should_quote', [['camelcase', 'reserved_word', 'space']]),
\   'table_column_query': {table -> printf(s:oracle_base_column_query, "AND C.table_name='".table."'")},
\ }

let s:mysql = {
\   'column_query': s:query,
\   'count_column_query': s:count_query,
\   'table_column_query': {table -> substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", '')},
\   'schemas_query': s:schema_query,
\   'schemas_parser': function('s:map_and_filter', ['\t']),
\   'requires_stdin': v:true,
\   'quote': ['`', '`'],
\   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
\   'column_parser': function('s:map_and_filter', ['\t']),
\   'count_parser': function('s:count_parser', [1])
\ }

let s:clickhouse_base_column_query = "SELECT table AS TABLE_NAME, name AS COLUMN_NAME FROM system.columns"
let s:clickhouse_query = s:clickhouse_base_column_query . " ORDER BY COLUMN_NAME ASC"
let s:clickhouse_count_query = "SELECT count() AS total FROM system.columns"
let s:clickhouse_schema_query = "SELECT DISTINCT database AS TABLE_SCHEMA, table AS TABLE_NAME FROM system.columns ORDER BY TABLE_SCHEMA, TABLE_NAME"
let s:clickhouse_table_column_query = s:clickhouse_base_column_query . " WHERE table = {db_tbl_name}"

let s:clickhouse = {
\   'args': ['--query'],
\   'column_query': s:clickhouse_query,
\   'count_column_query': s:clickhouse_count_query,
\   'table_column_query': {table -> substitute(s:clickhouse_table_column_query, '{db_tbl_name}', "'".table."'", '')},
\   'schemas_query': s:clickhouse_schema_query,
\   'schemas_parser': function('s:map_and_filter', ['\t']),
\   'quote': ['`', '`'],
\   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
\   'column_parser': function('s:map_and_filter', ['\t']),
\   'count_parser': function('s:count_parser', [0]),
\ }

" Not part of upstream. The 'interactive' dispatch this goes through (see
" vim_dadbod_completion.vim's s:generate_query, which always uses
" db#adapter#dispatch(db, 'interactive')) is `bq ... shell` for bigquery
" (see autoload/db/adapter/bigquery.vim) -- it prints a welcome banner,
" echoes its prompt inline right before the very first output line, and
" prints a final prompt + 'Goodbye.'. s:bigquery_strip_shell_noise strips
" all three so only real CSV rows reach the normal delimiter-based parsers
" below, same as every other backend already gets from its own CLI.
function! s:bigquery_strip_shell_noise(lines) abort
  let lines = filter(copy(a:lines), 'v:val !~# ''^Welcome to BigQuery''')
  if !empty(lines) && lines[-1] =~# 'Goodbye\.\s*$'
    call remove(lines, -1)
  endif
  if !empty(lines)
    let lines[0] = substitute(lines[0], '^\S\+>\s*', '', '')
  endif
  return lines
endfunction

" `bq shell` caps any query run inside it at 100 displayed rows, with no
" flag at the outer `bq ... shell` invocation to raise it (--max_rows is
" rejected there as unknown -- verified). Sending an explicit
" `query --max_rows=<n> ...` command as the shell's stdin instead of bare
" SQL bypasses it: that *inner* query subcommand does understand --max_rows
" (verified: 100 vs. the full ~300+ rows for the exact same underlying
" query). Matters here because a dataset's columns (column_query, scanning
" every table in it) or a project's tables (schemas_query, scanning every
" dataset) both routinely exceed 100 rows -- silently truncating to
" whatever happened to sort first, not an error, so it'd otherwise look
" like occasional-but-unexplained missing completions rather than a
" reproducible cap.
function! s:bigquery_shell_query(sql) abort
  return 'query --max_rows=100000 --nouse_legacy_sql "' . a:sql . '"'
endfunction

let s:bigquery_base_column_query = 'SELECT table_name, column_name FROM INFORMATION_SCHEMA.COLUMNS'
let s:bigquery_column_query = s:bigquery_shell_query(s:bigquery_base_column_query . ' ORDER BY column_name ASC')
let s:bigquery_count_query = s:bigquery_shell_query('SELECT COUNT(*) AS total FROM INFORMATION_SCHEMA.COLUMNS')
let s:bigquery_table_column_query = s:bigquery_base_column_query . ' WHERE table_name={db_tbl_name}'

let s:bigquery = {
      \ 'args': ['--format=csv'],
      \ 'requires_stdin': v:true,
      \ 'column_query': s:bigquery_column_query,
      \ 'count_column_query': s:bigquery_count_query,
      \ 'table_column_query': {table -> s:bigquery_shell_query(substitute(s:bigquery_table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \ 'quote': ['`', '`'],
      \ 'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
      \ 'column_parser': {result -> s:map_and_filter(',', s:bigquery_strip_shell_noise(result))},
      \ 'count_parser': {result -> s:count_parser(1, s:bigquery_strip_shell_noise(result))},
      \ }

" schemas_query (dataset-name completion for a project-only connection,
" e.g. `FROM dashboard_<Tab>` -> dashboard_ecommerce/dashboard_sav/...)
" needs a project-wide, region-qualified scan across every dataset, which
" needs bigquery.tables.list/routines.list at the dataset level -- IAM most
" accounts don't have by default (see autoload/db_ui/schemas.vim, which
" handles the drawer's dataset-tree browsing the same way once that
" permission exists). Unlike the drawer, this can't discover the project's
" region(s) itself: s:generate_query (vim_dadbod_completion.vim) always
" treats scheme.schemas_query as a fixed string evaluated once at
" script-load time, with no hook to inject a per-connection value, so it's
" gated behind an explicit g:vim_dadbod_completion_bigquery_region (set in
" database.lua) instead of auto-discovered -- correct schema completion for
" this one config, not a guess about what the region *would* be if unset.
if !exists('g:vim_dadbod_completion_bigquery_region')
  let g:vim_dadbod_completion_bigquery_region = ''
endif
if !empty(g:vim_dadbod_completion_bigquery_region)
  let s:bigquery.schemas_query = s:bigquery_shell_query(printf(
        \ 'SELECT table_schema, table_name FROM `%s`.INFORMATION_SCHEMA.TABLES',
        \ g:vim_dadbod_completion_bigquery_region))
  let s:bigquery.schemas_parser = {result -> s:map_and_filter(',', s:bigquery_strip_shell_noise(result))}
endif

let s:schemas = {
      \ 'postgres': s:postgres,
      \ 'postgresql': s:postgres,
      \ 'mysql': s:mysql,
      \ 'mariadb': s:mysql,
      \ 'oracle': s:oracle,
      \ 'sqlite': {
      \   'args': ['-list'],
      \   'column_query': "SELECT m.name AS table_name, ii.name AS column_name FROM sqlite_schema AS m, pragma_table_list(m.name) AS il, pragma_table_info(il.name) AS ii WHERE m.type='table' ORDER BY column_name ASC;",
      \   'count_column_query': "SELECT count(*) AS total FROM sqlite_schema AS m, pragma_table_list(m.name) AS il, pragma_table_info(il.name) AS ii WHERE m.type='table';",
      \   'table_column_query': {table -> substitute("SELECT m.name AS table_name, ii.name AS column_name FROM sqlite_schema AS m, pragma_table_list(m.name) AS il, pragma_table_info(il.name) AS ii WHERE m.type='table' AND table_name={db_tbl_name};", '{db_tbl_name}', "'".table."'", '')},
      \   'quote': ['"', '"'],
      \   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
      \   'column_parser': function('s:map_and_filter', ['|']),
      \   'count_parser': function('s:count_parser', [1]),
      \ },
      \ 'sqlserver': {
      \   'args': ['-h-1', '-W', '-s', '|', '-Q'],
      \   'column_query': s:query,
      \   'count_column_query': s:count_query,
      \   'table_column_query': {table -> substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", '')},
      \   'schemas_query': s:schema_query,
      \   'schemas_parser': function('s:map_and_filter', ['|']),
      \   'quote': ['[', ']'],
      \   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
      \   'column_parser': function('s:map_and_filter', ['|']),
      \   'count_parser': function('s:count_parser', [0])
      \ },
      \ 'clickhouse': s:clickhouse,
      \ 'bigquery': s:bigquery,
    \ }

function! vim_dadbod_completion#schemas#get(scheme)
  return get(s:schemas, a:scheme, {})
endfunction

function! vim_dadbod_completion#schemas#get_quotes_rgx() abort
  let open = []
  let close = []
  for db in values(s:schemas)
    if index(open, db.quote[0]) <= -1
      call add(open, db.quote[0])
    endif

    if index(close, db.quote[1]) <= -1
      call add(close, db.quote[1])
    endif
  endfor

  return {
        \ 'open': escape(join(open, '\|'), '[]'),
        \ 'close': escape(join(close, '\|'), '[]')
        \ }
endfunction
