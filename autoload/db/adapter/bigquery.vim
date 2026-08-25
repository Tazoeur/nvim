" Neovim's `:runtime {file}` (no bang, which is what db#adapter#call uses)
" only sources the FIRST match on 'runtimepath' -- and our config directory
" precedes vim.pack's plugin dirs there. So shipping a file at this same
" path fully shadows tpope/vim-dadbod's own autoload/db/adapter/bigquery.vim
" instead of complementing it: this file below is a verbatim copy of it
" (auth_input/command_for_url/filter/interactive, unchanged), plus #tables()
" (which upstream doesn't provide) for :DB completion, vim-dadbod-ui's
" drawer, and vim-dadbod-completion's table-name completion.
"
" Upstream: https://github.com/tpope/vim-dadbod/blob/master/autoload/db/adapter/bigquery.vim
function! db#adapter#bigquery#auth_input() abort
  return v:false
endfunction

" project:dataset -> region (lowercased, e.g. 'europe-west1'), discovered
" once via `bq show` and cached. Only used for the 'interactive' (bq shell)
" dispatch below -- that's what vim-dadbod-completion's own column/schema
" queries run through (see autoload/vim_dadbod_completion/schemas.vim),
" and they reference INFORMATION_SCHEMA.COLUMNS/etc. bare, relying on
" --dataset_id= alone for the default dataset. Bare INFORMATION_SCHEMA
" needs bq to know the dataset's actual location or it silently assumes
" 'US' and errors for any dataset outside it -- the same bug #tables() has,
" fixed there by qualifying the dataset directly in the query text instead
" (not an option for a query built from a static template elsewhere).
" Deliberately NOT added to 'filter' (bq query): that's what real query
" execution (:DB, :BqRun) and #tables() use, and forcing one dataset's
" region there could break a query that legitimately joins tables from a
" different region -- previously left to bq's own auto-inference from the
" tables actually referenced, unaffected by this.
let s:dataset_locations = {}

function! s:dataset_location(project, dataset) abort
  let key = a:project . ':' . a:dataset
  if has_key(s:dataset_locations, key)
    return s:dataset_locations[key]
  endif
  let location = ''
  try
    let decoded = json_decode(join(systemlist(['bq', '--project_id='.a:project, 'show', '--format=json', a:dataset]), ''))
    let location = tolower(get(decoded, 'location', ''))
  catch
  endtry
  let s:dataset_locations[key] = location
  return location
endfunction

function! s:command_for_url(url, subcmd, ...) abort
  let add_location = a:0 > 0 ? a:1 : v:false
  let cmd = ['bq']
  let parsed = db#url#parse(a:url)
  if has_key(parsed, 'opaque')
    let host_targets = split(substitute(parsed.opaque, '/', '', 'g'), ':')

    " If the host is specified as bigquery:project:dataset, then parse
    " the optional (project, dataset) to supply them to the CLI.
    if len(host_targets) == 2
      call add(cmd, '--project_id=' . host_targets[0])
      call add(cmd, '--dataset_id=' . host_targets[1])
      if add_location && !has_key(parsed.params, 'location')
        let location = s:dataset_location(host_targets[0], host_targets[1])
        if !empty(location)
          call add(cmd, '--location=' . location)
        endif
      endif
    elseif len(host_targets) == 1
      call add(cmd, '--project_id=' . host_targets[0])
    endif
  elseif !empty(get(parsed, 'host', ''))
    " Not part of upstream: bigquery://project (no dataset, no extra colon)
    " parses as a normal host-form URL (.host, not .opaque -- see
    " db_ui/schemas.vim's s:bigquery_project for the same distinction) and
    " fell through both branches above, silently never getting
    " --project_id= at all -- every 'bq' invocation for a project-only
    " connection relied entirely on gcloud's ambient default project
    " matching (accidentally correct here, not guaranteed, and one less
    " thing to depend on).
    call add(cmd, '--project_id=' . parsed.host)
  endif

  for [k, v] in items(parsed.params)
    let op = '--'.k.'='.v
    call add(cmd, op)
  endfor
  return cmd + [a:subcmd]
endfunction

function! db#adapter#bigquery#filter(url) abort
  return s:command_for_url(a:url, 'query')
endfunction

function! db#adapter#bigquery#interactive(url) abort
  return s:command_for_url(a:url, 'shell', v:true)
endfunction

" Not part of upstream: lists tables in the connection's dataset so :DB
" completion, vim-dadbod-ui's drawer and vim-dadbod-completion can use them.
"
" vim-dadbod-ui's drawer calls this synchronously (db_ui#drawer#populate_tables
" -> db#adapter#call(..., 'tables', ...)) and expects an immediate return --
" it has no async path here. A cold `bq query` (auth + INFORMATION_SCHEMA
" scan) can take 1-3s+, which would otherwise freeze the whole editor every
" time a BigQuery connection/dataset is expanded in the drawer for the first
" time. So: return whatever's cached right now (empty on the very first
" call), and kick off a background job that fills the cache and re-renders
" the drawer once the real list lands -- never block waiting on `bq`.
let s:tables_cache = {}
let s:tables_jobs = {}

function! db#adapter#bigquery#tables(url) abort
  let cmd = db#adapter#bigquery#filter(a:url)
  let dataset = matchstr(join(cmd, ' '), '--dataset_id=\zs\S*')
  if empty(dataset)
    return []
  endif
  if has_key(s:tables_cache, a:url)
    return s:tables_cache[a:url]
  endif
  if !has_key(s:tables_jobs, a:url)
    call s:fetch_tables(a:url, cmd, dataset)
  endif
  " First-ever ask for this connection: wait briefly for the real list
  " instead of handing back empty. Some callers (vim-dadbod-completion)
  " fetch a connection's tables exactly once, ever, and cache whatever they
  " got forever -- an empty answer here wouldn't just be "a bit stale", it'd
  " mean no table completion for the rest of the session. jobwait blocks
  " (still running the event loop, so s:tables_done below fires normally)
  " only until the job exits or this timeout hits; every later call for the
  " same url returns instantly from s:tables_cache regardless.
  if has_key(s:tables_jobs, a:url)
    call jobwait([s:tables_jobs[a:url]], 6000)
  endif
  return get(s:tables_cache, a:url, [])
endfunction

" Drops a connection's cached table list and re-fetches it in the
" background -- e.g. after creating a table that should now show up in the
" drawer without restarting Neovim.
function! db#adapter#bigquery#refresh_tables(url) abort
  if has_key(s:tables_cache, a:url)
    unlet s:tables_cache[a:url]
  endif
  call db#adapter#bigquery#tables(a:url)
endfunction

function! s:fetch_tables(url, cmd, dataset) abort
  let cmd = a:cmd + ['--format=csv', '--nouse_legacy_sql']
  let lines = ['']
  let job = jobstart(cmd, {
        \ 'on_stdout': function('s:job_collect', [lines]),
        \ 'on_stderr': function('s:job_collect', [lines]),
        \ 'on_exit': function('s:tables_done', [a:url, lines]),
        \ })
  if job <= 0
    return
  endif
  let s:tables_jobs[a:url] = job
  " Dataset backtick-qualified in the query itself, not left to an
  " unqualified INFORMATION_SCHEMA.TABLES relying on --dataset_id=: the
  " unqualified form additionally requires bq to know the dataset's
  " location, which it assumes is 'US' with no way to override here --
  " it silently fails (job exits nonzero, caught by s:tables_done below)
  " for any dataset outside that region. Qualifying the dataset directly
  " lets BigQuery resolve the location itself, no flag needed.
  call chansend(job, printf('SELECT table_name FROM `%s`.INFORMATION_SCHEMA.TABLES ORDER BY table_name', a:dataset))
  call chanclose(job, 'stdin')
endfunction

function! s:job_collect(lines, job_id, data, event) abort
  let a:lines[-1] .= a:data[0]
  call extend(a:lines, a:data[1:])
endfunction

function! s:tables_done(url, lines, job_id, status, event) abort
  call remove(s:tables_jobs, a:url)
  if a:status != 0
    return
  endif
  let lines = a:lines
  if !empty(lines) && empty(lines[-1])
    call remove(lines, -1)
  endif
  let s:tables_cache[a:url] = len(lines) > 1 ? lines[1:] : []
  " Only redraw if the drawer's actually open -- ui.vim/drawer.vim autoload
  " on first reference either way, so guard on the drawer window instead.
  " A plain render() only redraws the drawer's existing per-connection
  " state, it does NOT re-run populate_tables -- {'dbs': 1} makes it
  " actually re-populate first, so the now-warm s:tables_cache above gets
  " picked up instead of the stale empty list from the first ever call.
  if exists('*db_ui#drawer#get') && db_ui#drawer#get().is_opened()
    call db_ui#drawer#get().render({'dbs': 1})
  endif
endfunction
