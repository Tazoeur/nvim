" Sourced after $VIMRUNTIME/ftplugin/sql.vim, which leaves
" expandtab/tabstop/shiftwidth untouched -- so a plain SQL buffer inherits
" whatever the global defaults are (noexpandtab, tabstop=8), while
" indent/sqlanywhere.vim's auto-indent (BEGIN/IF/CASE blocks, parens) always
" indents by exactly one 'shiftwidth' per level. Pressing <Tab> and letting
" the buffer auto-indent should produce the same width, so pin all three
" together instead of relying on tabstop's fallback.
setlocal expandtab
setlocal tabstop=2
setlocal softtabstop=2
setlocal shiftwidth=2
