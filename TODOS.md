# TODOs

1. Commands are still leaking. (Write tests for everything first)

2. Add color flag and support non colored output.

3. Rewrite `write_command_help` to use text/tables

4. Generate md and man pages again.

5. Check for prealloc opportunities. i.e. `make([dynamic]string)` -> `make([dynamic]string, 5)`.

6. Add a text filter to the multi_select.

7. Add tests for untested commands.

8. procedures should be ordered by use, main at the top, then in the order they are called from main.

9. Shell completion

10. Bring back windows support / cross-compilation.

11. Test all cmds / terminal branches.

12. Pass allocator to findr?

13. Update `read_wire_string` to use a slice.

14. `-h` short flag seems to fail, at least with `envr list`

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
