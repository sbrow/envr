# envr command extern definitions for Nushell
# A tool for managing environment files and backups

export def tracked-paths [] {
  (
    ^envr list
    | from json
    | each {
      [$in.directory $in.path] | path join
    }
  )
}

export def untracked-paths [] {
  (
    ^envr scan
    | from json
  )
}

# Complete shell types for completion command
def shells [] {
  ["bash", "zsh", "fish", "powershell"]
}

export extern envr [
  ...args: any
  --help(-h)              # Show help information
  --toggle(-t)            # Help message for toggle
]

export extern "envr backup" [
  --help(-h) # Show help for backup command
  path: path@untracked-paths # Path to .env file to backup
]
#TODO: envr backup path.

export extern "envr check" [
  --help(-h)              # Show help for check command
]

export extern "envr completion" [
  shell: string@shells   # Shell to generate completion for
  --help(-h)                      # Show help for completion command
]

export extern "envr edit-config" [
  --help(-h)              # Show help for edit-config command
]

export extern "envr help" [
  command?: string        # Show help for specific command
]

export extern "envr init" [
  --help(-h)              # Show help for init command
]

export extern "envr list" [
  --help(-h)              # Show help for list command
]

export extern "envr remove" [
  --help(-h)              # Show help for remove command
  path: path@tracked-paths
]

export extern "envr restore" [
  --help(-h)              # Show help for restore command
  path: path@tracked-paths
]

export extern "envr scan" [
  --help(-h)              # Show help for scan command
]

export extern "envr sync" [
  --help(-h)              # Show help for sync command
]
