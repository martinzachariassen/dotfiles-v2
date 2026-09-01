# The only file this setup leaves in $HOME.
#
# zsh reads ~/.zshenv first, always. Pointing ZDOTDIR at ~/.config/zsh moves
# every other zsh file into the XDG tree, which is why there is no .zshrc,
# .zprofile or .zlogin cluttering the home directory.

export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
