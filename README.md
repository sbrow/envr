# envr - Backup your env files

Have you ever wanted to back up all your .env files in case your hard drive gets
nuked? `envr` makes it easier.

`envr` is a [Nushell](https://www.nushell.sh) script that tracks your `.env` files
in an encyrpted sqlite database. Changes can be effortlessly synced with
`envr sync`, and restored with `envr restore`.

`envr` puts all your .env files in one safe place, so you can back them up with
the tool [of your choosing](#backup-options).

## Features

- 🔐 **Encrypted Storage**: All `.env` files are encrypted using your ssh key and
[age](https://github.com/FiloSottile/age) encryption.
- 🔄 **Automatic Sync**: Update the database with one command, which can easily
be run on a cron.
- 🔍 **Smart Scanning**: Automatically discover and import `.env` files in your
home directory.
- 📝 **Multiple Config Formats**: Support for many configuration formats,
including: JSON, TOML, YAML, INI, XML, and NUON.
- [ ] TODO: 🗂️ **Rename Detection**: Automatically handle renamed repositories.
- ✨ **Interactive CLI**: User-friendly prompts for file selection and management
thanks to [nushell](https://www.nushell.sh/)

## TODOS

- [ ] Allow configuration of ssh key.
- [ ] Allow multiple ssh keys.

## Prerequisites

- An SSH key pair (for encryption/decryption)
- The following binaries:
   - [nushell](https://www.nushell.sh/)
   - [age](https://github.com/FiloSottile/age)
   - [fd](https://github.com/sharkdp/fd)
   - [sqlite3](https://github.com/sqlite/sqlite)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/username/envr.git
   cd envr
   ```
2. Install [dependencies](#prerequisites).
3. Configure nushell.

## Quick Start

1. **Initialize envr**:
   ```bash
   nu mod.nu envr init
   ```
   This will create your configuration file and set up encrypted storage.

2. **Scan for existing .env files**:
   ```bash
   nu mod.nu envr scan
   ```
   Select files you want to back up from the interactive list.

3. **List tracked files**:
   ```bash
   nu mod.nu envr list
   ```

4. **Sync your environment files**:
   ```bash
   nu mod.nu envr sync
   ```

## Disclaimers

> [!CAUTION]
> Do not lose your SSH key pair! Your backup will be **lost forever**.

## Commands

| Command | Description |
|---------|-------------|
| `envr init [format]` | Initialize envr with configuration file |
| `envr backup <file>` | Back up a specific .env file |
| `envr restore [path]` | Restore a backed-up .env file |
| `envr list` | View all tracked environment files |
| `envr scan` | Search for and selectively back up .env files |
| `envr sync` | Synchronize all tracked files (backup changes, restore missing) |
| `envr remove [...paths]` | Remove files from backup storage |
| `envr edit config` | Edit your configuration file |
| `envr config show` | Display current configuration |

## Configuration

The configuration file is created during initialization and supports multiple formats:

```toml
# Example ~/.envr/config.toml
source = "~/.envr/config.toml"
priv_key = "~/.ssh/id_ed25519"
pub_key = "~/.ssh/id_ed25519.pub"

[scan]
matcher = "\.env"
exclude = "*.envrc"
include = "~"
```

## Backup Options

`envr` merely gathers your `.env` files in one local place. It is up to you to
back up the database (found at ~/.envr/data.age) to a *secure* and *remote*
location.

### Git

### restic

## License

This project is licensed under the [MIT License](./LICENSE).

## Support

For issues, feature requests, or questions, please
[open an issue](https://github.com/sbrow/envr/issues).
