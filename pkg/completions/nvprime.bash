# bash completion for nvprime
# Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>

_nvprime() {
    local cur prev words cword
    _init_completion || return

    local commands="
        status info caps
        core power display
        dlss reflex stream
        daemon config
        help version
    "

    local core_cmds="clocks pstate boost info"
    local power_cmds="status limit fan thermal efficiency"
    local display_cmds="status vrr hdr monitors"
    local dlss_cmds="status enable disable quality"
    local reflex_cmds="status enable disable boost"
    local stream_cmds="start stop status config"

    case "${prev}" in
        nvprime)
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            return
            ;;
        core)
            COMPREPLY=($(compgen -W "${core_cmds}" -- "${cur}"))
            return
            ;;
        power)
            COMPREPLY=($(compgen -W "${power_cmds}" -- "${cur}"))
            return
            ;;
        display)
            COMPREPLY=($(compgen -W "${display_cmds}" -- "${cur}"))
            return
            ;;
        dlss)
            COMPREPLY=($(compgen -W "${dlss_cmds}" -- "${cur}"))
            return
            ;;
        reflex)
            COMPREPLY=($(compgen -W "${reflex_cmds}" -- "${cur}"))
            return
            ;;
        stream)
            COMPREPLY=($(compgen -W "${stream_cmds}" -- "${cur}"))
            return
            ;;
        quality)
            COMPREPLY=($(compgen -W "ultra_performance performance balanced quality dlaa" -- "${cur}"))
            return
            ;;
        limit)
            COMPREPLY=($(compgen -W "50 75 100 125 150" -- "${cur}"))
            return
            ;;
        --gpu|-g)
            COMPREPLY=($(compgen -W "0 1 2 3" -- "${cur}"))
            return
            ;;
    esac

    case "${cur}" in
        -*)
            COMPREPLY=($(compgen -W "--help --version --gpu --json --verbose" -- "${cur}"))
            return
            ;;
    esac

    COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
}

complete -F _nvprime nvprime
