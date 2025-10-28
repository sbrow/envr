#!/usr/bin/env nu

# Manage your .env files with ease
export def envr [] {
  help envr
}

# Import a .env file into envr
export def "envr import" [
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

  $"file '($file)' imported successfull!"
}

const db_path = '/home/spencer/.envr/data.age'

# Create or load the database
def "open db" [] {
  if (not ($db_path | path exists)) {
    create-db
  } else {
    # Open the db
    let dec = mktemp -p ~/.envr;
    age -d -i ((envr config show).priv_key | path expand) $db_path | save -f $dec
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
export def "envr config init" [
  format?: string
  #identity?: path
] {
  mkdir ~/.envr

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
    save $source
  }
}

# View your tracked files
export def "envr list" [] {
  (
    open db
    | query db 'select * from envr_env_files'
    | update remotes { from json }
    | reject contents
  )
}

# Update your env backups
export def "envr sync" [] {
  'TODO:' 
}

# Edit your config
export def "envr config edit" [] {
  'TODO:'
}

def "config-file" []: [nothing -> path nothing -> nothing] {
  ls ~/.envr/config.* | get 0.name -o
}

# show your current config
export def "envr config show" []: nothing -> record<source: path, priv_key: path, pub_key: path> {
  open (config-file)
}
