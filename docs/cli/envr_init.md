## envr init

Set up envr

### Synopsis

The init command generates your initial config and saves it to
~/.envr/config in JSON format.

During setup, you will be prompted to select one or more ssh keys with which to
encrypt your databse. **Make 100% sure** that you have **a remote copy** of this
key somewhere, otherwise your data could be lost forever.

```
envr init [flags]
```

### Options

```
  -f, --force   Overwrite an existing config
  -h, --help    help for init
```

### SEE ALSO

* [envr](envr.md)	 - Manage your .env files.

