## envr restore

Restore a .env file from the database

```
envr restore <path> [flags]
```

**Arguments:**

* `path` — Path to .env file to restore

Remote files are restored over SSH using an atomic replacement. If the remote
file has changed since it was backed up, restoration is refused unless
`--force` is specified.

### Options

```
  -h, --help          show this documentation
  -c, --config-file   config file (default "~/.envr/config.json")
      --color         Whether or not to colorize output (default 'auto')
  -f, --force         Overwrite existing config
```

### SEE ALSO

* [envr](envr.md)	 - Manage your .env files.
