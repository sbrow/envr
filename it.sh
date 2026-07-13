
_envr() {
    local cur prev cmd
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cmd="${COMP_WORDS[1]}"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "init scan sync backup add restore list remove check version edit-config completion" -- "$cur") )
        return
    fi

    case "$prev" in
        --config-file|-c)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return
            ;;
        --output|-o)
            COMPREPLY=( $(compgen -W "auto table json" -- "$cur") )
            return
            ;;
        --color)
            COMPREPLY=( $(compgen -W "auto always never" -- "$cur") )
            return
            ;;
    esac

    case "$cur" in -*)
        case "$cmd" in
            init)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --color --force -f" -- "$cur") )
                return
                ;;
            scan)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --color" -- "$cur") )
                return
                ;;
            sync)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --output -o --color" -- "$cur") )
                return
                ;;
            backup|add)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --color" -- "$cur") )
                return
                ;;
            restore)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --color" -- "$cur") )
                return
                ;;
            list)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --output -o --color" -- "$cur") )
                return
                ;;
            remove)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --color" -- "$cur") )
                return
                ;;
            check)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --color" -- "$cur") )
                return
                ;;
            version)
                COMPREPLY=( $(compgen -W "--help -h" -- "$cur") )
                return
                ;;
            edit-config)
                COMPREPLY=( $(compgen -W "--help -h --config-file -c --color" -- "$cur") )
                return
                ;;
            completion)
                COMPREPLY=( $(compgen -W "--help -h" -- "$cur") )
                return
                ;;
        esac
        ;;
    esac

    case "$cmd" in
        backup|add)
            COMPREPLY=( $(compgen -W "$(envr scan --output json 2>/dev/null)" -- "$cur") )
            return
            ;;
        restore)
            COMPREPLY=( $(compgen -W "$(envr list --output json 2>/dev/null)" -- "$cur") )
            return
            ;;
        remove)
            COMPREPLY=( $(compgen -W "$(envr list --output json 2>/dev/null)" -- "$cur") )
            return
            ;;
        completion)
            COMPREPLY=( $(compgen -W "nushell bash" -- "$cur") )
            return
            ;;
    esac

}

complete -F _envr envr
