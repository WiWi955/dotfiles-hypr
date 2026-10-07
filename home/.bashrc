# Omarchy environment (OMARCHY_PATH + PATH), needed even for non-interactive shells
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap

# If not running interactively, don't do anything else (leave this above the rc source)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source "$OMARCHY_PATH/default/bash/rc"

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

# Custom kaomoji prompt (replaces the starship prompt).
# Starship rewrites PS1 before every prompt, so drop its hook first.
PROMPT_COMMAND="${STARSHIP_PROMPT_COMMAND-}"
PS1='\[\e[35m\]༼ つ◕_◕ ༽つ\[\e[m\] \[\e[36m\]:\[\e[m\] \[\e[36m\]:\[\e[m\] \[\e[36m\][\[\e[m\]\[\e[35m\]\u\[\e[m\]\[\e[36m\]]\[\e[m\] \[\e[36m\]\w\[\e[m\]\[\e[36m\]\$\[\e[m\] '

# Terminal banner (ported from dotfiles-hypr fastfetch config).
fastfetch -c ~/.config/fastfetch/banner.jsonc

# To-do list (widget will.todo dans la barre)
#   list              → affiche les tâches
#   add <texte>       → ajoute une tâche, ex : add Acheter du pain
list() { omarchy-shell will.todo list; }
add() { [[ $# -gt 0 ]] && omarchy-shell will.todo add "$*" >/dev/null; }
