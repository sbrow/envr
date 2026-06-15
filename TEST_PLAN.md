# Test Coverage Plan

## Current State

- 101 tests, all passing
- Strong coverage: crypto (100%), ssh (90%), db CRUD + env_file + update_dir, config save/load + paths, scan, features, cant_scan, parse_args
- Misleading test files: `cmd_check_test`, `cmd_list_test`, `cmd_nushell_completion_test` don't test their namesake procs
- Biggest remaining gap: all `cmd_*` handlers untested

## Next: `load_config` / `save_config` path param + `-c`/`--config-file` flag
- Refactor `load_config(path: string = "")` and `save_config(cfg, force, path: string = "")` — empty string defaults to `~/.envr/config.json`
- Add `-c`/`--config-file` to `parse_args` (now testable)
- Wire through `main.odin` so commands receive the config path
- Unblocks command handler tests with fixture configs

## Command handlers (need DB + filesystem fixtures)

### `cmd_version` (cmd_version.odin)
- Test default output (prints VERSION)
- Capture stdout, assert content

### `cmd_list` (cmd_list.odin)
- Test TTY path: fixture DB with rows, capture table output
- Test non-TTY path: capture JSON output, unmarshal and verify keys/values
- Test empty DB: verify clean output (empty table or `[]`)

### `cmd_backup` (cmd_backup.odin)
- Test successful backup: valid path, verify `db_insert` called
- Test missing file: verify error message
- Test duplicate backup: verify rejection or update behavior

### `cmd_remove` (cmd_remove.odin)
- Test successful removal: existing entry, verify `db_delete` called
- Test removal of non-existent entry: verify error or no-op

### `cmd_restore` (cmd_restore.odin)
- Test successful restore: entry exists in DB, verify file written to correct path
- Test restore of missing entry: verify error
- Test directory creation: restore to path with missing parent dirs

## Hard to test (interactive / external deps)

### `cmd_deps` (cmd_deps.odin)
- Needs `git` and/or `fd` in PATH
- Test TTY and non-TTY paths
- Skip if dependencies not available (with `#assert` like TODO 28 suggests)

### `cmd_scan` (cmd_scan.odin)
- Needs `fd` installed
- Test with fixture git repo containing `.env` files
- Test `find_unbacked` integration (already partially tested in `cmd_check_test.odin`)
- Non-TTY JSON output path

### `cmd_edit_config` (cmd_edit_config.odin)
- Needs refactoring: extract `$EDITOR` parsing into testable helper (TODO 12)
- Test multi-word editor values (`"code -w"`)
- Test missing `$EDITOR`

### `cmd_init` (cmd_init.odin)
- Interactive prompt makes this hard
- Needs refactoring: extract SSH key discovery and config generation into testable procs
- Test `--force` flag behavior

### `prompt.odin`
- Needs refactoring to be testable
- `render_options` could be tested if it accepted an `io.Writer`
- `read_key` could be tested with a pipe/redirect instead of raw stdin
- `multi_select` is end-to-end interactive, likely integration test only

## Notes

- All command handler tests will need stdout capture. Consider extracting a helper or using `io.Writer` injection.
- DB integration tests should use in-memory SQLite (`:memory:`) where possible.
- Temp dir fixtures should follow the pattern in `scan_test.odin`.
- External dependency tests (`fd`, `git`) should use `#assert` to ensure the dependency is present rather than silently skipping (TODO 28).
- Tests that manipulate the `HOME` env var must use a mutex to prevent races with parallel test execution.
