#compdef nvprime
# zsh completion for nvprime
# Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>

_nvprime() {
    local -a commands
    commands=(
        'status:Show overall GPU status'
        'info:Display detailed GPU information'
        'caps:Show GPU capabilities'
        'core:GPU core management (clocks, P-states)'
        'power:Power and thermal management'
        'display:Display pipeline control (VRR, HDR)'
        'dlss:DLSS control and configuration'
        'reflex:Reflex low-latency control'
        'stream:Game streaming control'
        'daemon:Run as background service'
        'config:Configuration management'
        'help:Show help information'
        'version:Show version information'
    )

    local -a core_cmds
    core_cmds=(
        'clocks:Show/set GPU clocks'
        'pstate:P-state management'
        'boost:Boost clock control'
        'info:Core subsystem info'
    )

    local -a power_cmds
    power_cmds=(
        'status:Power status overview'
        'limit:Power limit control'
        'fan:Fan speed control'
        'thermal:Thermal management'
        'efficiency:Efficiency mode'
    )

    local -a display_cmds
    display_cmds=(
        'status:Display status'
        'vrr:VRR/G-Sync control'
        'hdr:HDR management'
        'monitors:Monitor information'
    )

    local -a dlss_cmds
    dlss_cmds=(
        'status:DLSS status'
        'enable:Enable DLSS'
        'disable:Disable DLSS'
        'quality:Set quality mode'
    )

    local -a reflex_cmds
    reflex_cmds=(
        'status:Reflex status'
        'enable:Enable Reflex'
        'disable:Disable Reflex'
        'boost:Toggle Reflex Boost'
    )

    local -a stream_cmds
    stream_cmds=(
        'start:Start streaming'
        'stop:Stop streaming'
        'status:Streaming status'
        'config:Stream configuration'
    )

    local -a quality_modes
    quality_modes=(
        'ultra_performance:Maximum performance, lowest quality'
        'performance:High performance'
        'balanced:Balanced quality and performance'
        'quality:High quality'
        'dlaa:Deep Learning Anti-Aliasing'
    )

    _arguments -C \
        '(-h --help)'{-h,--help}'[Show help]' \
        '(-v --version)'{-v,--version}'[Show version]' \
        '(-g --gpu)'{-g,--gpu}'[GPU index]:gpu:(0 1 2 3)' \
        '--json[Output in JSON format]' \
        '--verbose[Verbose output]' \
        '1: :->command' \
        '2: :->subcommand' \
        '*:: :->args'

    case $state in
        command)
            _describe -t commands 'nvprime command' commands
            ;;
        subcommand)
            case $words[1] in
                core)
                    _describe -t core_cmds 'core command' core_cmds
                    ;;
                power)
                    _describe -t power_cmds 'power command' power_cmds
                    ;;
                display)
                    _describe -t display_cmds 'display command' display_cmds
                    ;;
                dlss)
                    _describe -t dlss_cmds 'dlss command' dlss_cmds
                    ;;
                reflex)
                    _describe -t reflex_cmds 'reflex command' reflex_cmds
                    ;;
                stream)
                    _describe -t stream_cmds 'stream command' stream_cmds
                    ;;
            esac
            ;;
        args)
            case $words[1],$words[2] in
                dlss,quality)
                    _describe -t quality_modes 'quality mode' quality_modes
                    ;;
            esac
            ;;
    esac
}

_nvprime "$@"
