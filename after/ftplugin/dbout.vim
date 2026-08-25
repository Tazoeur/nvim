" vim-dadbod-ui's own ftplugin/dbout.vim sets foldmethod=expr (one fold per
" result table, via db_ui#dbout#foldexpr) and then does `normal!zo` to open
" the fold under the cursor -- but that ftplugin is sourced when the results
" buffer is created, before the query's output is actually written into it,
" so the fold it opens isn't the real one. The result: every query lands
" behind a single closed fold ("+-- N lines: ...") until manually opened.
" Simplest fix is to just not fold results at all.
setlocal nofoldenable
