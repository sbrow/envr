## envr sync

Update or restore your env backups

For both local and remote files, `sync` backs up changed file contents and
restores missing files from the backup. Remote SSH and permission errors are
reported instead of being treated as missing files.

```
envr sync [flags]
```

### Options

```
  -h, --help          show this documentation
  -c, --config-file   config file (default "~/.envr/config.json")
  -o, --output        the format of output data (default 'table')
      --color         Whether or not to colorize output (default 'auto')
```

### SEE ALSO

* [envr](envr.md)	 - Manage your .env files.
