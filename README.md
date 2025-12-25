# nvim-tester

A lightweight Neovim testing helper:

- Uses Tree-sitter to locate the nearest function/method at the cursor
- Generate or jump to the corresponding test in one step
- Run the current test and send output to quickfix

## Supported languages

- Go
- Python
- Rust

## Setup

```lua
require("tester").setup({
  languages = {
    go = {
      root_markers = { "go.mod", ".git" },
    },
    python = {
      root_markers = { "pyproject.toml", "setup.py", ".git" },
    },
    rust = {
      root_markers = { "Cargo.toml", ".git" },
    },
  },
})
```

You can also use `vim.g.tester = { ... }` before startup if preferred.

## Commands

Buffer-local commands are registered based on filetype:

- `:GOTest` / `:GOTestRun`
- `:PYTHONTest` / `:PYTHONTestRun`
- `:RUSTTest` / `:RUSTTestRun`

`TestRun` supports `!`:

- `:XxxTestRun` runs the nearest test at cursor.
- `:XxxTestRun!` runs all tests in current file when supported.

## Run strategy

- Go: `go test -v -run <func> ./...`
- Python: `pytest -v -k <func> <file>`
- Rust: `cargo test <func>`

If `vim-dispatch` is installed, it will run via `:Dispatch` first.

## Configuration options

- `languages.<lang>.root_markers`: project root detection markers.
- `languages.<lang>.qf.efm`: errorformat used to parse test output into quickfix (optional).
- `languages.<lang>.commands.single`: override single-test command (string or function).
- `languages.<lang>.commands.file`: override file-level command (string or function).
- `languages.<lang>.template`: override generated test template.

## Notes

- Requires Tree-sitter parsers for the corresponding languages.
- Generated test templates are placeholders; adjust assertions/imports per project.
