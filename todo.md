## TODO

* for the plugin that displays the keybinds as they are used, create some menus names for nested key combinations so it's pretty instead of [4 more]

* bqls (BigQuery LSP) doesn't resolve unqualified `dataset.table` references
  (2-part, backtick-quoted or not) -- it only finds a table via the fully
  qualified `project.dataset.table` (3-part). Confirmed by talking to the
  real `bqls` binary directly over stdio (bypassing Neovim entirely): every
  2-part form of `orders.orders_successful` reports `Table not found`, while
  `happyhoursmarketdev.orders.orders_successful` resolves cleanly -- and this
  is independent of the `project_id`/`location` settings pushed via
  `root_dir`/`on_init` in `lua/lsp.lua` (that fix is still worth keeping, but
  it can't fix this -- it's a bug/limitation inside bqls's own table-preload
  code, `Catalog.PreloadTablesFromAST` in `catalog.go`, which silently
  swallows the underlying error). Bare 2-part refs are exactly what DBUI's
  ad-hoc query buffers naturally end up using, since `vim.g.dbs` only has a
  project-only `bigquery://happyhoursmarketdev` connection.
  - Future fix: feed bqls a *virtual, fully-qualified* SQL buffer instead of
    the DBUI buffer's raw text -- rewrite bare `dataset.table` to
    `happyhoursmarketdev.dataset.table` before bqls sees it, the same way
    `lua/dbt.lua` + `BqCompiled` already materialize a dbt model's resolved
    Jinja into a virtual buffer for a human to read. Doing this for bqls
    itself means routing the LSP through that resolved buffer (e.g. via
    `textDocument/didOpen`/`didChange` on a shadow URI) rather than the
    real one.
  - Note: dbt model buffers feed bqls raw, unresolved Jinja today (`{{
    ref(...) }}` etc.) -- that's not even valid SQL, so bqls presumably
    chokes on it even harder than the 2-part case. The same virtual/resolved
    buffer plumbing should cover both cases at once.
* when inside a .sql file that is linked to a bigquery thing, always have completion for the name of the project (in my case it's often happyhoursmarketdev)
* bug: when leader-f (code format) inside sql (bqls), I have double message saying that it cannot (because dbt formatting)
* try to use a dbt lsp instead of a bigquery lsp, because bq lsp crash when seeing {{
* setup quicklist jump to next/previous with (left-alt)+l/h
* dadbod-ui `dbout` result buffers (`vim-dadbod-ui/ftplugin/dbout.vim`) already
  fold each result table via `db_ui#dbout#foldexpr` -- a fold starts on a
  header line immediately followed by a `----` separator, so when a buffer
  holds multiple result sets (e.g. several statements run via `:DB` in one
  go), each is its own top-level fold. Vim's built-in `zj`/`zk` already jump
  to the start of the next/previous fold, which is exactly "next/previous
  result set" here -- they just aren't bound to the same `(left-alt)+l/h`
  used for quickfix nav (`lua/keymaps.lua:38-39`).
  - Fix: add a `FileType dbout` autocmd (alongside the existing `sql` one in
    `lua/database.lua`) that buffer-locally maps `<A-l>` -> `zjzo` and
    `<A-h>` -> `zkzo` (the trailing `zo` opens the fold so the result is
    visible after jumping, since folds start closed by default). Keep the
    global `cnext`/`cprev` binds in `keymaps.lua` untouched -- this is a
    buffer-local override for `dbout` only, not a replacement.
* change keymap <leader>-U to leader-uu
* bigquery lsp is removing comments when formatting, I don't want that behavior
