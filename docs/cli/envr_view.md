## envr view

View a backed-up .env file

If no path is provided, the user will be asked to select one from a list. You may also pass the number from the "#" column of `envr list` instead of the full path. If a partial path is passed, the closest match will be opened.

```
envr view [path] [flags]
```

### Arguments

* `path` — Path or substring, or number of a backed-up file. (optional)

### Options

```
  -h, --help          show this documentation
  -c, --config-file   config file (default "~/.envr/config.json")
      --color         Whether or not to colorize output (default 'auto')
  -p, --stdout        Print file contents directly to stdout instead of using a pager
```

### SEE ALSO

* [envr](envr.md)	 - Manage your .env files.
