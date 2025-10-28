#!/usr/bin/env nu
#
# TODO: Wrap blocks that use tmp files in try so we can clean them up.

use std assert;

# Manage your .env files with ease
@example "Set up envr" { envr init }
export def envr [] {
  help envr
}

# Import a .env file into envr
export def "envr backup" [
  file: path
] {
  cd (dirname $file);

  let contents = (open $file --raw)

  open db

  let row = {
    path: $file
    dir: (pwd)
    remotes: (git remote | lines | each { git remote get-url $in } | to json)
    sha256: ($contents | hash sha256)
    contents: $contents
  };

  try {
    $row | stor insert -t envr_env_files
  } catch {
    $row | stor update -t envr_env_files -w $'path == "($row.path)"'
  }

  close db

  $"file '($file)' backed up!"
}

const db_path = '~/.envr/data.age'

# Create or load the database
def "open db" [] {
  if (not ($db_path | path exists)) {
    create-db
  } else {
    # Open the db
    let dec = mktemp -p ~/.envr;
    let priv_key = ((envr config show).priv_key | path expand);
    age -d -i $priv_key ($db_path | path expand) | save -f $dec
    stor import -f $dec
    rm $dec
  }

  stor open
}

def "create-db" []: nothing -> any {
  let dec = mktemp -p ~/.envr;

  sqlite3 $dec 'create table envr_env_files (
      path text primary key not null
    , dir text not null
    , remotes text -- JSON
    , sha256 text not null
    , contents text not null
  );'

  let pub_key = ((envr config show).pub_key | path expand);
  age -R $pub_key $dec | save -f $db_path

  stor import -f $dec
  rm $dec;
}

def "close db" [] {
  let dec = mktemp -p ~/.envr;

  stor export --file-name $dec;

  # Encrypt the file
  let pub_key = ((envr config show).pub_key | path expand);
  age -R $pub_key $dec | save -f $db_path

  rm $dec
}

# Restore a .env file from backup
export def "envr restore" [
  path?: path # The path of the file to restore. Will be prompted if left blank.
]: nothing -> string {
  let files = (files)
  let $path = if ($path | is-empty) {
    (
      $files
      | select path dir remotes
      | input list -f "Please select a file to restore"
      | get path
    )
  } else {
    $path
  }

  let file = ($files | where path == $path | first);
  assert ($file | is-not-empty) "File must be found"

  let response = if (($path | path type) == 'file') {
    if (open --raw $file.path | hash sha256 | $in == $file.sha256) {
      # File matches
      $'(ansi yellow)file is already up to date.(ansi reset)';
    } else {
      # File exists, but doesn't match
      let continue = (
        [No Yes]
        | input list $"File '($path)' already exists, are you sure you want to overwrite it?"
        | $in == 'Yes'
      );

      if ($continue) {
        null
      } else {
        $'(ansi yellow)No action was taken(ansi reset)'
      }
    }
  };

  if ($response | is-empty) {
    # File should be restored
    $file.contents | save -f $path
    return $'(ansi green)($path) restored!(ansi reset)'
  } else {
    return $response
  }
}

# Supported config formats
const available_formats = [
  json
  toml
  yaml
  ini
  xml
  nuon
]

# Create your initial config
export def "envr init" [
  format?: string
  #identity?: path
]: nothing -> record {
  mkdir ~/.envr

  if (glob ~/.envr/config.* | length | $in > 0) {
    error make {
      msg: "A config file already exists"
      label: {
        text: ""
        span: (metadata $format).span
      }
    }
  } else {
    let format = if ($format | is-empty) {
      $available_formats | input list 'Please select the desired format for your config file'
    }

    let identity = '~/.ssh/id_ed25519';
  
    # The path to the config file.
    let source = $'~/.envr/config.($format)'

    {
      source: $source
      priv_key: $identity
      pub_key: $'($identity).pub'
    } | tee {
      save $source;
      open db
    }
  }
}

# View your tracked files
export def "envr list" [] {
  (files | reject contents)
}

# List all the files in the database
def files [] {
  (
    open db
    | query db 'select * from envr_env_files'
    | update remotes { from json }
  )
}

# Update your env backups
export def "envr sync" [] {
  'TODO:' 
}

# Search for .env files
export def "envr scan" [] {
  'TODO:' 
}

# Edit your config
export def "envr edit config" [] {
  ^$env.EDITOR (config-file)
}

def "config-file" []: [nothing -> path nothing -> nothing] {
  ls ~/.envr/config.* | get 0.name -o
}

# show your current config
def "envr config show" []: nothing -> record<source: path, priv_key: path, pub_key: path> {
  open (config-file)
}
