# TODO

Note: These todos can wait until all the subcommands have been ported.

## HIGH

1. **db.odin:380-383, 405, 446** — `sqlite.bind_text` return values overwritten but never checked. A failed bind means `sqlite.step` operates on unbound params.

## MEDIUM

2. **db.odin:324-327** — Map iteration (`remote_set`) is non-deterministic. Same file can produce different JSON on each backup, causing spurious DB diffs. Sort remotes before storing.

3. **db.odin:135, 250** — String interpolation into SQL (`VACUUM INTO '%s'`, `ATTACH DATABASE '%s'`). Currently safe because input is controlled, but fragile.

4. **features.odin:30-41** — `find_binary` uses `strings.join` instead of `filepath.join`, uses `os.stat` instead of checking executability, hardcodes `:` as PATH separator (wrong on Windows).

5. **cmd_restore.odin:20-30 & cmd_remove.odin:19-29** — Identical path-resolution block copy-pasted. `is_abs` guard is redundant since `filepath.abs` is a no-op on absolute paths. Extract a helper.

6. **cmd_restore.odin:44** — `os.mkdir_all` error silently discarded. Subsequent write failure will be confusing.

7. **cmd_edit_config.odin:27** — `$EDITOR` used as single binary name. Breaks for multi-word values like `"code -w"`. Needs `strings.fields()`.

8. **config.odin:178** — `search_paths` silently ignores `os.user_home_dir` error. If home is empty, `~` isn't expanded. Same class of bug as issue 3.

9. **prompt.odin:124** — `make([dynamic]bool, len(options))` creates N zero-initialized elements. Works because `false` is the default, but same footgun as original issue 1. Should be `make([dynamic]bool, 0, len(options))`.

## LOW

10. **db.odin:115** — `json.unmarshal_string` error not checked. Malformed JSON silently produces empty/partial data.

11. **db.odin:352-353** — `hex.encode` error ignored. `string(hex_bytes)` aliases the byte slice.

12. **cmd_sync.odin:80, cmd_list.odin:33, cmd_deps.odin:9** — `make([]string, 2)` for table rows never freed. Leaks per row. Defer to memory pass.

## REFACTOR

13. **cmd_list.odin** — Non-TTY branch builds `ListEntry` structs and marshals JSON separately. Now that `render_json_rows` (issue 1) accepts an `io.Writer` and uses `json.marshal`, unify both branches to use it. Note: will change JSON keys from `"directory"/"path"` to `"Directory"/"Path"`.

14. Check for prealloc opportunities. i.e. `make([dynamic]string)` -> `make([dynamic]string, 5)`.

15. Add a text filter to the multi_select.

16. Create backup / fallback fd.

17. Add tests for untested commands.

18. 2 scan tests silently skip when fd isn't installed, tests pass without actually testing anything. These should use #assert to be sure that fd is in path.

19. Try to do all encryption / decryption in memory - only read / write encrypted data to disk.

20. add --format -f flag to commands that draw tables.

21. Replace `testing.expect` calls with `testing.expect_value` calls where appropriate.

22. Change struct field names from PascalCase to snake_case.

## Double-check AI output

- [ ] cli.odin
- [ ] cli_test.odin
- [x] cmd_backup.odin
- [x] cmd_check.odin
- [ ] cmd_check_test.odin
- [x] cmd_deps.odin
- [ ] cmd_edit_config.odin
- [x] cmd_init.odin
- [x] cmd_list.odin
- [ ] cmd_list_test.odin
- [x] cmd_nushell_completion.odin
- [x] cmd_nushell_completion_test.odin
- [x] cmd_remove.odin
- [x] cmd_restore.odin
- [x] cmd_scan.odin
- [x] cmd_sync.odin
- [x] cmd_version.odin
- [ ] config.odin
- [ ] config_test.odin
- [ ] crypto.odin
- [ ] crypto_test.odin
- [ ] db.odin
- [ ] db_integration_test.odin
- [ ] db_test.odin
- [x] features.odin
- [x] features_test.odin
- [x] main.odin
- [x] prompt.odin
- [ ] scan.odin
- [ ] scan_test.odin
- [ ] sodium.odin
- [ ] sqlite/sqlite.odin
- [ ] ssh.odin
- [ ] ssh_test.odin
- [ ] table.odin
- [ ] table_test.odin
