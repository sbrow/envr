## envr init

Set up envr

### Synopsis

The init command generates your initial config and saves it to
~/.envr/config in JSON format.\n\nDuring setup, you will be prompted to select one or more ssh keys with which to
encrypt your databse. **Make 100% sure** that you have **a remote copy** of this
key somewhere, otherwise your data could be lost forever.

```
envr init [flags]
```

### Options

```
  -h, --help          show this documentation
  -c, --config-file   config file (default "~/.envr/config.json")
      --color         Whether or not to colorize output (default 'auto')
  -f, --force         Overwrite existing config
```

### SEE ALSO

* [envr](envr.md)	 - Manage your .env files.
