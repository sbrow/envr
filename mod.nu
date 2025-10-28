#!/usr/bin/env nu

# Manage your .env files with ease
def main [] {
  
}

def "main get" [
  file: path
] {
  cd (dirname $file);

  {
    path: $file
    dir: (pwd)
    remotes: (git remote | lines | each { git remote get-url $in })
    contents: (open $file --raw)
  }
}
