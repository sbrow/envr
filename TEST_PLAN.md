# Test Coverage Plan

## Current State

- 60 tests, all passing
- Strong coverage: crypto (100%), ssh (80%), scan, features
- Misleading test files: `cmd_check_test`, `cmd_list_test`, `cmd_nushell_completion_test` don't test their namesake procs
- Biggest gap: `db.odin` (15/21 procs untested), all `cmd_*` handlers untested, `parse_args` untested

## Tier 1 — Easy wins (pure functions, minimal setup)

### 1. `render_table` (table.odin)
- Follow existing `render_json_rows` test pattern
- Test cases: normal data (verify box-drawing chars, column alignment), empty rows, wide unicode, single column
- Assert against `strings.Builder` output

### 2. `parse_args` (cli.odin)
- Test cases: bare command, `--flag value`, `-f value`, positional args, `--help`/`-h`, unknown command, no args (prints usage), flag without value (error)
- High value — this is the entry point for all command dispatch

### 3. `is_encrypted_key` (ssh.odin)
- Test cases: encrypted key (returns true), unencrypted key (returns false), RSA key, malformed key
- Fills last gap in ssh.odin

## Tier 2 — High value, medium effort (fixtures exist)

### 4. `db.odin` CRUD layer
Largest gap in the project. Infrastructure already in `db_integration_test.odin` (`fixture_key`, `fixture_db_path`, in-memory DB setup).

Procs to test:
- `db_open` / `db_close` — open in-memory DB, verify handle valid
- `db_insert` — insert a row, verify it persists
- `db_fetch` — fetch existing row, fetch missing row (returns false)
- `db_delete` — delete existing row (returns true), delete missing row (returns false)
- `db_list` — list multiple rows, empty DB
- `db_vacuum_to_file` — vacuum to temp file, verify file exists and is non-empty

Test pattern: create in-memory DB via `db_open`, insert fixture rows, query and assert, `defer db_close`.

### 5. `load_config` / `save_config` (config.odin)
- `save_config`: write a `Config` to temp dir, verify file exists and contents are valid JSON
- `load_config`: read back a config written by `save_config`, round-trip assert
- `load_config` error case: missing file returns error
- Need a temp dir fixture (pattern exists in `scan_test.odin`)

## Tier 3 — Command handlers (need DB + filesystem fixtures)

### 6. `cmd_version` (cmd_version.odin)
- Test default output (prints VERSION)
- Test `--long`/`-l` flag output
- Capture stdout, assert content

### 7. `cmd_list` (cmd_list.odin)
- Test TTY path: fixture DB with rows, capture table output
- Test non-TTY path: capture JSON output, unmarshal and verify keys/values
- Test empty DB: verify clean output (empty table or `[]`)

### 8. `cmd_backup` (cmd_backup.odin)
- Test successful backup: valid path, verify `db_insert` called
- Test missing file: verify error message
- Test duplicate backup: verify rejection or update behavior

### 9. `cmd_remove` (cmd_remove.odin)
- Test successful removal: existing entry, verify `db_delete` called
- Test removal of non-existent entry: verify error or no-op

### 10. `cmd_restore` (cmd_restore.odin)
- Test successful restore: entry exists in DB, verify file written to correct path
- Test restore of missing entry: verify error
- Test directory creation: restore to path with missing parent dirs

## Tier 4 — Hard to test (interactive / external deps)

### 11. `cmd_deps` (cmd_deps.odin)
- Needs `git` and/or `fd` in PATH
- Test TTY and non-TTY paths
- Skip if dependencies not available (with `#assert` like TODO 28 suggests)

### 12. `cmd_scan` (cmd_scan.odin)
- Needs `fd` installed
- Test with fixture git repo containing `.env` files
- Test `find_unbacked` integration (already partially tested in `cmd_check_test.odin`)
- Non-TTY JSON output path

### 13. `cmd_edit_config` (cmd_edit_config.odin)
- Needs refactoring: extract `$EDITOR` parsing into testable helper (TODO 12)
- Test multi-word editor values (`"code -w"`)
- Test missing `$EDITOR`

### 14. `cmd_init` (cmd_init.odin)
- Interactive prompt makes this hard
- Needs refactoring: extract SSH key discovery and config generation into testable procs
- Test `--force` flag behavior

### 15. `prompt.odin`
- Needs refactoring to be testable
- `render_options` could be tested if it accepted an `io.Writer`
- `read_key` could be tested with a pipe/redirect instead of raw stdin
- `multi_select` is end-to-end interactive, likely integration test only

## Notes

- All command handler tests will need stdout capture. Consider extracting a helper or using `io.Writer` injection.
- DB integration tests should use in-memory SQLite (`:memory:`) where possible.
- Temp dir fixtures should follow the pattern in `scan_test.odin`.
- External dependency tests (`fd`, `git`) should use `#assert` to ensure the dependency is present rather than silently skipping (TODO 28).
