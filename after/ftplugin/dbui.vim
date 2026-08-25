" Sourced after vim-dadbod-ui's own ftplugin/dbui.vim, which binds
" o/<CR>/<2-LeftMouse> to <Plug>(DBUI_SelectLine) (drawer.vim's
" toggle_line('edit')) -- the generic expand/collapse/open action for every
" node in the tree (connection, "Schemas", one dataset, one table, a saved
" query, ...).
"
" Wraps <CR>/o (not <2-LeftMouse>, keyboard nav only) to additionally warm
" column metadata (name/type/description, see lua/bq_schema.lua) for a
" dataset right when it's expanded: a schema-node item's own `type` field is
" exactly 'schemas->items-><dataset>' (drawer.vim's
" _render_schemas_section), with no further '->' -- a table under it is
" 'schemas->items-><dataset>->tables->items-><table>' -- so that shape alone
" identifies a schema row and gives us the dataset name, no need to touch
" drawer.vim itself.
function! s:on_select_line() abort
  let drawer = db_ui#drawer#get()
  let item = drawer.get_current_item()
  let after_prefix = matchstr(item.type, '^schemas->items->\zs.*$')
  let is_schema = !empty(after_prefix) && stridx(after_prefix, '->') ==# -1
  let was_expanded = is_schema && get(item, 'expanded', 0)

  " Same call <Plug>(DBUI_SelectLine) makes (drawer.vim: toggle_line('edit')
  " bound to o/<CR>/<2-LeftMouse>) -- toggle_line() is a plain dict method
  " on the object db_ui#drawer#get() already hands out, so this needs no
  " <Plug>/normal-mode indirection.
  call drawer.toggle_line('edit')

  " was_expanded means it just got expanded (toggle_line flips it) --
  " ignore the collapse direction.
  if is_schema && !was_expanded
    let project = matchstr(get(db_ui#get_conn_info(item.dbui_db_key_name), 'url', ''), '^bigquery://\zs[^:/]*')
    if !empty(project)
      call v:lua.require('bq_schema').ensure(project, after_prefix)
    endif
  endif
endfunction

nnoremap <buffer><silent> <CR> :call <SID>on_select_line()<CR>
nnoremap <buffer><silent> o :call <SID>on_select_line()<CR>
