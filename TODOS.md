# TODO

Note: These todos can wait until all the subcommands have been ported.

## HIGH

1. [x] **table.odin:74-89** — Hand-rolled JSON output doesn't escape `"`, `\`, newlines. Reimplements `json.marshal` which is already imported in `cmd_list.odin`. Replace with `json.marshal`.

2. **db.odin:380-383, 405, 446** — `sqlite.bind_text` return values overwritten but never checked. A failed bind means `sqlite.step` operates on unbound params.

3. **config.odin:52-54** — `os.user_home_dir` error silently ignored. If it fails, `home` is `""` and all paths become relative (`".envr"` instead of `"~/.envr"`).

30. **cmd_sync.odin:46-50, 64-68** — Double `db_insert` when `BackedUp`: first insert on line 48, then `db_update_required` is also true for `BackedUp` so second insert runs on line 65. Redundant and wasteful.

## MEDIUM

4. **db.odin:29-35** — `make_temp_path` never calls `strings.builder_destroy`. Leaks builder buffer every call.

5. **db.odin:324-327** — Map iteration (`remote_set`) is non-deterministic. Same file can produce different JSON on each backup, causing spurious DB diffs. Sort remotes before storing.

6. **db.odin:470-473** — `string_to_cstring` allocates via `strings.clone_to_cstring` and never frees. Called dozens of times across db operations.

7. **db.odin:470, 462** — Both `string_to_cstring` and `cstring_to_string` ignore allocation errors. A nil cstring gets passed to SQLite (UB).

8. **db.odin:135, 250** — String interpolation into SQL (`VACUUM INTO '%s'`, `ATTACH DATABASE '%s'`). Currently safe because input is controlled, but fragile.

9. **features.odin:30-41** — `find_binary` uses `strings.join` instead of `filepath.join`, uses `os.stat` instead of checking executability, hardcodes `:` as PATH separator (wrong on Windows).

10. **cmd_restore.odin:20-30 & cmd_remove.odin:19-29** — Identical path-resolution block copy-pasted. `is_abs` guard is redundant since `filepath.abs` is a no-op on absolute paths. Extract a helper.

11. **cmd_restore.odin:44** — `os.mkdir_all` error silently discarded. Subsequent write failure will be confusing.

12. **cmd_edit_config.odin:27** — `$EDITOR` used as single binary name. Breaks for multi-word values like `"code -w"`. Needs `strings.fields()`.

13. [x] **cmd_list.odin:31-35, 58-61** — Uses a `strings.Builder` (never destroyed) for what is just `row.Dir + "/"`. Also `filepath.rel` used where `filepath.base` would suffice since dir is always the parent.

33. **config.odin:178** — `search_paths` silently ignores `os.user_home_dir` error. If home is empty, `~` isn't expanded. Same class of bug as issue 3.

34. **table.odin:84-88** — `render_json_rows` creates `map[string]string` per row, copies into dynamic array. `delete(entries)` frees the array but not individual map internals — potential map bucket leak per row.

35. **prompt.odin:124** — `make([dynamic]bool, len(options))` creates N zero-initialized elements. Works because `false` is the default, but same footgun as original issue 1. Should be `make([dynamic]bool, 0, len(options))`.

## LOW

14. [x] **db.odin:338-341** — Unnecessary `strings.clone` before `filepath.dir` (which already returns a slice into the input).

15. **db.odin:115** — `json.unmarshal_string` error not checked. Malformed JSON silently produces empty/partial data.

16. **db.odin:352-353** — `hex.encode` error ignored. `string(hex_bytes)` aliases the byte slice.

18. **config.odin:51-60** — `envr_dir` recomputes home dir on every call. Could cache.

19. **main.odin:42-46** — Dynamic array in `fallback_to_go` never deleted. Harmless since process exits.

36. **cli.odin:59-76** — Single-dash multi-char flags (e.g. `-force`) silently misparse. `-force` becomes flag `f` with value `o`, then `rce` as positional arg. Only `--force` and `-f` work correctly.

37. **cmd_sync.odin:80, cmd_list.odin:33, cmd_deps.odin:9** — `make([]string, 2)` for table rows never freed. Leaks per row. Defer to memory pass.

## REFACTOR

20. **cmd_list.odin** — Non-TTY branch builds `ListEntry` structs and marshals JSON separately. Now that `render_json_rows` (issue 1) accepts an `io.Writer` and uses `json.marshal`, unify both branches to use it. Note: will change JSON keys from `"directory"/"path"` to `"Directory"/"Path"`.

21. Check for prealloc opportunities. i.e. `make([dynamic]string)` -> `make([dynamic]string, 5)`.

22. Replace is_tty with terminal.is_terminal

23. Add a text filter to the multi_select.

24. Create backup / fallback fd.

25. Add tests for untested commands.

26. Add a global --config -c flag to use an alternate config.

27. version --long Odin only prints version; Go also prints commit hash and build date

28. 2 scan tests silently skip	Low	When fd isn't installed, tests pass without actually testing anything. These should use #assert to be sure that fd is in path.

29. nushell completions?
