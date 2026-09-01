# Aliases. Every replacement here is a package in this module's Brewfile or in
# core/Brewfile -- if you remove the package, remove the alias.

alias ls='eza --group-directories-first'
alias ll='eza -l --group-directories-first --git'
alias la='eza -la --group-directories-first --git'
alias tree='eza --tree'
alias cat='bat --paging=never'
alias grep='rg'

alias g='git'
alias gs='git status --short --branch'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'

alias ..='cd ..'
alias ...='cd ../..'

# Reapply the dotfiles after pulling.
alias dotup='git -C "$HOME/Developer/personal/dotfiles-v2" pull --ff-only && dot apply'
