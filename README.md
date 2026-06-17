# envr - Backup your env files

Have you ever wanted to back up all your .env files in case your hard drive gets
nuked? `envr` makes it easier.

`envr` is a binary application that tracks your `.env` files
in an encyrpted sqlite database. Changes can be effortlessly synced with
`envr sync`, and restored with `envr restore`.

`envr` puts all your .env files in one safe place, so you can back them up with
the tool [of your choosing](#backup-options).

## Features

- **Encrypted Storage**: All `.env` files are encrypted using your ssh key and
[libsodium](https://github.com/jedisct1/libsodium). 
- **Automatic Sync**: Update the database with one command, which can easily
be run on a cron.
- **Smart Scanning**: Automatically discover and import `.env` files in your
home directory.
- **Rename Detection**: Automatically find and updates renamed/moved
repositories.

## TODOS
- [x] Rename Detection: automatically update moved files.
- [ ] Allow use of keys from `ssh-agent`
- [x] Allow configuration of ssh key.
- [x] Allow multiple ssh keys.

## Installation

You will need an SSH key pair for encryption and decryption. You can generate one
with `ssh-keygen -t ed25519`. It will be saved to `~/.ssh/id_ed25519`.

### With Odin

If you already have `odin` installed:

```bash
# You'll need libsodium and sqlite
odin build -o:speed
envr init
```

### With Nix

If you are a [nix](https://nixos.org/) user

#### Try it out

```bash
nix run github.com:sbrow/envr --
```

#### Install it

```nix
# /etc/nixos/configuration.nix
{ config, envr, system, ... }: {
  environment.systemPackages = [
    envr.packages.${system}.default
  ];
}
```

## Quick Start

Check out the [man page](./docs/cli/envr.md) for the quick setup guide.

## Disclaimers

> [!CAUTION]
> Do not lose your SSH key pair! Your backup will be **lost forever**.

## Commands

See [the docs](./docs/cli) for the current list of available commands.

## Configuration

The configuration file is created during initialization:

```jsonc
# Example ~/.envr/config.json
{
  "keys": [
    {
      "private": "/home/ubuntu/.ssh/id_ed25519",
      "public": "/home/ubuntu/.ssh/id_ed25519.pub"
    }
  ],
  "scan": {
    "matcher": "\\.env",
    "exclude": [
      "*\\.envrc",
      "\\.local/",
      "node_modules",
      "vendor"       
    ],
    "include": "~"
  }
}
```

## Backup Options

`envr` merely gathers your `.env` files in one local place. It is up to you to
back up the database (found at `~/.envr/data.envr`) to a *secure* and *remote*
location.

### Git

`envr` preserves inodes when updating the database, so you can safely hardlink
`~/.envr/data.envr` into your [GNU Stow](https://www.gnu.org/software/stow/),
[Home Manager](https://github.com/nix-community/home-manager), or
[NixOS](https://nixos.wiki/wiki/flakes) repository.

> [!CAUTION]
> For **maximum security**, only save your `data.envr` file to a local
(i.e. non-cloud) git server that **you personally control**.
>
> I take no responsibility if you push all your secrets to a public GitHub repo.

### restic

[restic](https://restic.readthedocs.io/en/latest/010_introduction.html).

## License

This project is licensed under the [MIT License](./LICENSE).

## Support

For issues, feature requests, or questions, please
[open an issue](https://github.com/sbrow/envr/issues).
