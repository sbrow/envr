# TODOs

1. Commands are still leaking.

2. **db.odin** — Inconsistencies in how struct vs sqlite are named.

3. Add color flag and support non colored output.

4. Use text/tables for command output

5. Generate md and man pages again.

6. Json may be an expensive encoding for remotes. Confirm with spall, and use null terminated strings if necessary.

7. Make sure official path separators are used when appropriate, rather than '/'.

8. **cmd_restore.odin:20-30 & cmd_remove.odin:19-29** — Identical path-resolution block copy-pasted. `is_abs` guard is redundant since `filepath.abs` is a no-op on absolute paths. Extract a helper.

9. **cmd_restore.odin:44** — `os.mkdir_all` error silently discarded. Subsequent write failure will be confusing.

10. **config.odin:178** — `search_paths` silently ignores `os.user_home_dir` error. If home is empty, `~` isn't expanded. Same class of bug as issue 3.

12. Consistently ignore allocator errors

13. **cmd_sync.odin:80, cmd_list.odin:33** — `make([]string, 2)` for table rows never freed. Leaks per row. Defer to memory pass.

14. Check for prealloc opportunities. i.e. `make([dynamic]string)` -> `make([dynamic]string, 5)`.

15. Add a text filter to the multi_select.

16. Add tests for untested commands.

17. 2 scan tests silently skip when fd isn't installed, tests pass without actually testing anything. These should use #assert to be sure that fd is in path.

18. add --format -f flag to commands that draw tables.

19. Replace `testing.expect` calls with `testing.expect_value` calls where appropriate.

20. Change struct field names from PascalCase to snake_case.

21. procedures should be ordered by use, main at the top, then in the order they are called from main.

22. Shell completion

23. Bring back windows support / cross-compilation.

24. Test all cmds / terminal branches.

25. Replace `fmt.tprintf("/tmp/envr-test-...-%d", os.get_pid())` + `os.mkdir_all` in test files with `os.mkdir_temp` (race-free, honors `$TMPDIR`, matches `findr/test_env.odin` pattern).

26. Adopt `core:log` across `db.odin`, `crypto.odin`, `config.odin`, `ssh.odin` — replace ~30 scattered `fmt.printf("Error ...")` calls with leveled logging for consistent stderr routing and source locations.

27. "Encryption failed" in tests. 

28. Pass allocator to findr?

29. Update `read_wire_string` to use a slice.

## Double-check AI output

- [ ] cli.odin
- [ ] cli_test.odin
- [x] colors.odin
- [x] cmd_backup.odin
- [x] cmd_check.odin
- [ ] cmd_check_test.odin
- [x] cmd_edit_config.odin
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
- [x] config.odin
- [ ] config_test.odin
- [ ] crypto.odin
- [ ] crypto_test.odin
- [ ] db.odin
- [ ] db_integration_test.odin
- [ ] db_test.odin
- [x] main.odin
- [x] prompt.odin
- [x] scan.odin
- [ ] scan_test.odin
- [ ] sodium.odin
- [x] sqlite/sqlite.odin
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
