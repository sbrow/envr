# TODOs

1. Consider giving db its own allocator

2. **db.odin:324-327** — Map iteration (`remote_set`) is non-deterministic. Same file can produce different JSON on each backup, causing spurious DB diffs. Sort remotes before storing.

3. **db.odin:135, 250** — String interpolation into SQL (`VACUUM INTO '%s'`, `ATTACH DATABASE '%s'`). Currently safe because input is controlled, but fragile.

4. **features.odin:30-41** — `find_binary` uses `strings.join` instead of `filepath.join`, uses `os.stat` instead of checking executability, hardcodes `:` as PATH separator (wrong on Windows).

5. **cmd_restore.odin:20-30 & cmd_remove.odin:19-29** — Identical path-resolution block copy-pasted. `is_abs` guard is redundant since `filepath.abs` is a no-op on absolute paths. Extract a helper.

6. **cmd_restore.odin:44** — `os.mkdir_all` error silently discarded. Subsequent write failure will be confusing.

8. **config.odin:178** — `search_paths` silently ignores `os.user_home_dir` error. If home is empty, `~` isn't expanded. Same class of bug as issue 3.

10. **db.odin:115** — `json.unmarshal_string` error not checked. Malformed JSON silently produces empty/partial data.

11. **db.odin:352-353** — `hex.encode` error ignored. `string(hex_bytes)` aliases the byte slice.

12. **cmd_sync.odin:80, cmd_list.odin:33, cmd_deps.odin:9** — `make([]string, 2)` for table rows never freed. Leaks per row. Defer to memory pass.

13. **cmd_list.odin** — Non-TTY branch builds `ListEntry` structs and marshals JSON separately. Now that `render_json_rows` (issue 1) accepts an `io.Writer` and uses `json.marshal`, unify both branches to use it. Note: will change JSON keys from `"directory"/"path"` to `"Directory"/"Path"`.

14. Check for prealloc opportunities. i.e. `make([dynamic]string)` -> `make([dynamic]string, 5)`.

15. Add a text filter to the multi_select.

17. Add tests for untested commands.

18. 2 scan tests silently skip when fd isn't installed, tests pass without actually testing anything. These should use #assert to be sure that fd is in path.

20. add --format -f flag to commands that draw tables.

21. Replace `testing.expect` calls with `testing.expect_value` calls where appropriate.

22. Change struct field names from PascalCase to snake_case.

23. procedures should be ordered by use, main at the top, then in the order they are called from main.

24. Remove git dependency.

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
- [ ] findr/findr_test.odin
- [ ] findr/gitignore.odin
- [ ] findr/gitignore_test.odin
- [ ] findr/glob.odin
- [ ] findr/glob_test.odin
- [ ] findr/repos.odin
- [ ] findr/test_env.odin
- [ ] findr/walker.odin
