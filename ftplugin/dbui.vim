" Sourced before vim-dadbod-ui's own ftplugin/dbui.vim: this config
" directory precedes vim.pack's plugin dirs on 'runtimepath', and
" `:filetype plugin on` sources every matching ftplugin/dbui.vim across the
" whole runtimepath in that order, not just the first.
"
" db_ui#utils#set_mapping (autoload/db_ui/utils.vim) skips binding a key
" whenever something already maps to the same <Plug> target (hasmapto
" check) -- the plugin's own designed override hook. Its ftplugin binds
" <C-j>/<C-k> to GotoLastSibling/GotoFirstSibling, which shadows
" vim-tmux-navigator's global <C-j>/<C-k> window/tmux-pane navigation
" (plugin/tmux_navigator.vim) while the cursor is in the drawer. Pre-binding
" those two <Plug> targets here to g]/g[ instead means dbui's own ftplugin
" sees them already mapped and never touches <C-j>/<C-k> at all -- so
" tmux-navigator's global mapping just applies in the drawer like
" everywhere else, and first/last sibling still work, just relocated.
nmap <buffer><nowait> g] <Plug>(DBUI_GotoLastSibling)
nmap <buffer><nowait> g[ <Plug>(DBUI_GotoFirstSibling)
