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

function! s:command_for_url(url, subcmd) abort
  let cmd = ['bq']
  let parsed = db#url#parse(a:url)
  if has_key(parsed, 'opaque')
    let host_targets = split(substitute(parsed.opaque, '/', '', 'g'), ':')

    " If the host is specified as bigquery:project:dataset, then parse
    " the optional (project, dataset) to supply them to the CLI.
    if len(host_targets) == 2
      call add(cmd, '--project_id=' . host_targets[0])
      call add(cmd, '--dataset_id=' . host_targets[1])
    elseif len(host_targets) == 1
      call add(cmd, '--project_id=' . host_targets[0])
    endif
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
  return s:command_for_url(a:url, 'shell')
endfunction

" Not part of upstream: lists tables in the connection's dataset so :DB
" completion, vim-dadbod-ui's drawer and vim-dadbod-completion can use them.
function! db#adapter#bigquery#tables(url) abort
  let cmd = db#adapter#bigquery#filter(a:url)
  if match(join(cmd, ' '), '--dataset_id=') < 0
    return []
  endif
  let cmd += ['--format=csv', '--nouse_legacy_sql']
  let lines = db#systemlist(cmd, 'SELECT table_name FROM INFORMATION_SCHEMA.TABLES ORDER BY table_name')
  return len(lines) > 1 ? lines[1:] : []
endfunction
