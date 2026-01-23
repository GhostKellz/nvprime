# fish completion for nvprime
# Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>

# Disable file completion by default
complete -c nvprime -f

# Global options
complete -c nvprime -s h -l help -d 'Show help'
complete -c nvprime -s v -l version -d 'Show version'
complete -c nvprime -s g -l gpu -d 'GPU index' -xa '0 1 2 3'
complete -c nvprime -l json -d 'Output in JSON format'
complete -c nvprime -l verbose -d 'Verbose output'

# Main commands
complete -c nvprime -n __fish_use_subcommand -a status -d 'Show overall GPU status'
complete -c nvprime -n __fish_use_subcommand -a info -d 'Display detailed GPU information'
complete -c nvprime -n __fish_use_subcommand -a caps -d 'Show GPU capabilities'
complete -c nvprime -n __fish_use_subcommand -a core -d 'GPU core management'
complete -c nvprime -n __fish_use_subcommand -a power -d 'Power and thermal management'
complete -c nvprime -n __fish_use_subcommand -a display -d 'Display pipeline control'
complete -c nvprime -n __fish_use_subcommand -a dlss -d 'DLSS control'
complete -c nvprime -n __fish_use_subcommand -a reflex -d 'Reflex low-latency control'
complete -c nvprime -n __fish_use_subcommand -a stream -d 'Game streaming control'
complete -c nvprime -n __fish_use_subcommand -a daemon -d 'Run as background service'
complete -c nvprime -n __fish_use_subcommand -a config -d 'Configuration management'
complete -c nvprime -n __fish_use_subcommand -a help -d 'Show help'
complete -c nvprime -n __fish_use_subcommand -a version -d 'Show version'

# Core subcommands
complete -c nvprime -n '__fish_seen_subcommand_from core' -a clocks -d 'Show/set GPU clocks'
complete -c nvprime -n '__fish_seen_subcommand_from core' -a pstate -d 'P-state management'
complete -c nvprime -n '__fish_seen_subcommand_from core' -a boost -d 'Boost clock control'
complete -c nvprime -n '__fish_seen_subcommand_from core' -a info -d 'Core subsystem info'

# Power subcommands
complete -c nvprime -n '__fish_seen_subcommand_from power' -a status -d 'Power status overview'
complete -c nvprime -n '__fish_seen_subcommand_from power' -a limit -d 'Power limit control'
complete -c nvprime -n '__fish_seen_subcommand_from power' -a fan -d 'Fan speed control'
complete -c nvprime -n '__fish_seen_subcommand_from power' -a thermal -d 'Thermal management'
complete -c nvprime -n '__fish_seen_subcommand_from power' -a efficiency -d 'Efficiency mode'

# Display subcommands
complete -c nvprime -n '__fish_seen_subcommand_from display' -a status -d 'Display status'
complete -c nvprime -n '__fish_seen_subcommand_from display' -a vrr -d 'VRR/G-Sync control'
complete -c nvprime -n '__fish_seen_subcommand_from display' -a hdr -d 'HDR management'
complete -c nvprime -n '__fish_seen_subcommand_from display' -a monitors -d 'Monitor information'

# DLSS subcommands
complete -c nvprime -n '__fish_seen_subcommand_from dlss' -a status -d 'DLSS status'
complete -c nvprime -n '__fish_seen_subcommand_from dlss' -a enable -d 'Enable DLSS'
complete -c nvprime -n '__fish_seen_subcommand_from dlss' -a disable -d 'Disable DLSS'
complete -c nvprime -n '__fish_seen_subcommand_from dlss' -a quality -d 'Set quality mode'

# DLSS quality modes
complete -c nvprime -n '__fish_seen_subcommand_from dlss; and __fish_seen_subcommand_from quality' -a ultra_performance -d 'Maximum performance'
complete -c nvprime -n '__fish_seen_subcommand_from dlss; and __fish_seen_subcommand_from quality' -a performance -d 'High performance'
complete -c nvprime -n '__fish_seen_subcommand_from dlss; and __fish_seen_subcommand_from quality' -a balanced -d 'Balanced'
complete -c nvprime -n '__fish_seen_subcommand_from dlss; and __fish_seen_subcommand_from quality' -a quality -d 'High quality'
complete -c nvprime -n '__fish_seen_subcommand_from dlss; and __fish_seen_subcommand_from quality' -a dlaa -d 'Deep Learning AA'

# Reflex subcommands
complete -c nvprime -n '__fish_seen_subcommand_from reflex' -a status -d 'Reflex status'
complete -c nvprime -n '__fish_seen_subcommand_from reflex' -a enable -d 'Enable Reflex'
complete -c nvprime -n '__fish_seen_subcommand_from reflex' -a disable -d 'Disable Reflex'
complete -c nvprime -n '__fish_seen_subcommand_from reflex' -a boost -d 'Toggle Reflex Boost'

# Stream subcommands
complete -c nvprime -n '__fish_seen_subcommand_from stream' -a start -d 'Start streaming'
complete -c nvprime -n '__fish_seen_subcommand_from stream' -a stop -d 'Stop streaming'
complete -c nvprime -n '__fish_seen_subcommand_from stream' -a status -d 'Streaming status'
complete -c nvprime -n '__fish_seen_subcommand_from stream' -a config -d 'Stream configuration'
