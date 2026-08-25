# nvim config

## Requirements

Neovim itself, plus these system dependencies:

- **Neovim >= 0.12** (needed for the built-in `vim.pack` plugin manager)
- **git** - fetches plugins via `vim.pack`
- **A C compiler** (`build-essential` on Ubuntu/Debian, i.e. `gcc`/`cc`) -
  required by `nvim-treesitter` (main branch) to build parsers, and by Mason
  to build any tool that has no prebuilt binary for your platform
- **Rust + Cargo** (via [rustup](https://rustup.rs)) - used to install the
  `tree-sitter` CLI
- **tree-sitter CLI** (`cargo install tree-sitter-cli`) - `nvim-treesitter`
  (main branch) shells out to `tree-sitter build` to compile parsers; without
  it and a C compiler, `:TSUpdate`/`TSInstall` fail with
  `ENOENT ... 'tree-sitter'`
  - On Ubuntu, `cargo install tree-sitter-cli` can fail while building
    `rquickjs-sys` with `fatal error: 'stdbool.h' file not found`, even with
    `gcc`/`libc6-dev` installed - libclang (used by `bindgen`) fails to find
    gcc's own header dir. Work around it with:
    `BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/15/include" cargo install tree-sitter-cli`
    (adjust the `15` to your installed gcc version)
- **ripgrep** (`rg`) - Telescope live grep and hidden-file search
  (`lua/navigation.lua`)
- **fzf** - not required as a CLI; only used if you separately install
  `telescope-fzf-native.nvim` (not included by default)

### dbt / BigQuery editing (`lua/database.lua`, `lua/dbt.lua`)

Only needed if you use the BigQuery/dbt editor keymaps (`<leader>b*`):

- **`bq`** (Google Cloud SDK's BigQuery CLI) - runs dry-run cost estimates and
  real queries against BigQuery
- **`dbt`** (dbt-core or dbt-fusion, on `PATH`) - compiles dbt model Jinja
  (`ref`/`source`/`config`/macros) before running/estimating a query
- A configured **gcloud** auth / BigQuery project - required for `bq` to work

## Install (Ubuntu/Debian)

```bash
sudo apt install -y build-essential ripgrep

# rustup (provides cargo)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

cargo install tree-sitter-cli
```

Then open nvim - `vim.pack` and Mason will install the rest (LSP servers,
plugins, treesitter parsers) automatically.
