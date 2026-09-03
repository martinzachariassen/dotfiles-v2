# The only zsh file in $HOME: ZDOTDIR moves the rest into the XDG tree.
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

# Here, not .zshrc: git can be invoked without an interactive shell. Absolute
# path test, not `command -v`: PATH gains Homebrew only later, in path.zsh.
# `--wait` or `code` returns instantly and git commits an empty message.
if [[ -x /opt/homebrew/bin/code ]]; then
  export EDITOR='code --wait'
  export VISUAL="$EDITOR"
fi
