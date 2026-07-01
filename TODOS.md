# TODOs

1. Bring back windows support / cross-compilation.

2. Commands are still leaking. (Write tests for everything first)

3. procedures should be ordered by use, main at the top, then in the order they are called from main.

4. Check for prealloc opportunities. i.e. `make([dynamic]string)` -> `make([dynamic]string, 5)`.

5. Test all cmds / terminal branches.

6. Generate md and man pages again.

7. Bash Shell completion

8. Add tests for untested commands.

9. Audit ssh.odin for places where `#no_bounds_check` would be appropriate.

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
- [ ] flags.odin
- [x] main.odin
- [ ] prompt.odin
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
