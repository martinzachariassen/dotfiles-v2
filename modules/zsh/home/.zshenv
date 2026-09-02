# The only file this setup leaves in $HOME.
#
# zsh reads ~/.zshenv first, always. Pointing ZDOTDIR at ~/.config/zsh moves
# every other zsh file into the XDG tree, which is why there is no .zshrc,
# .zprofile or .zlogin cluttering the home directory.

export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

# Editor. Here rather than .zshrc because git can be invoked by something that
# never starts an interactive shell, and an unset $EDITOR drops it into vi.
#
# `--wait` is not optional: without it `code` forks and returns instantly, so
# git commits an empty message and `dot config` reads the file back unedited.
#
# Absolute path and a file test, not `command -v`: .zshenv runs for EVERY zsh
# including every script, and $PATH gains Homebrew only in path.zsh, which
# .zshrc sources later. The guard means enabling zsh without apps leaves
# $EDITOR unset and callers fall back to vi, rather than pointing at nothing.
if [[ -x /opt/homebrew/bin/code ]]; then
  export EDITOR='code --wait'
  export VISUAL="$EDITOR"
fi
