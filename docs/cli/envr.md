## envr

Manage your .env files.

### Synopsis

envr keeps your .env synced to a local, age encrypted database.
Is a safe and eay way to gather all your .env files in one place where they can
easily be backed by another tool such as restic or git.

All your data is stored in ~/data.age

Getting started is easy:

1. Create your configuration file and set up encrypted storage:

> envr init

2. Scan for existing .env files:

> envr scan

Select the files you want to back up from the interactive list.

3. Verify that it worked:

> envr list

4. After changing any of your .env files, update the backup with:

> envr sync

5. If you lose a repository, after re-cloning the repo into the same path it was
at before, restore your backup with:

> envr restore ~/&lt;path to repository&gt;/.env

### Options

```
  -h, --help   help for envr
```

### SEE ALSO

* [envr backup](envr_backup.md)	 - Import a .env file into envr
* [envr deps](envr_deps.md)	 - Check for missing binaries
* [envr edit-config](envr_edit-config.md)	 - Edit your config with your default editor
* [envr init](envr_init.md)	 - Set up envr
* [envr list](envr_list.md)	 - View your tracked files
* [envr nushell-completion](envr_nushell-completion.md)	 - Generate custom completions for nushell
* [envr remove](envr_remove.md)	 - Remove a .env file from your database
* [envr restore](envr_restore.md)	 - Install a .env file from the database into your file system
* [envr scan](envr_scan.md)	 - Find and select .env files for backup
* [envr sync](envr_sync.md)	 - Update or restore your env backups
* [envr version](envr_version.md)	 - Show envr's version

