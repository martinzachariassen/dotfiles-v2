#!/usr/bin/env bash
#
# The price of the XDG layout, made loud.
#
# ~/.zshenv points ZDOTDIR at ~/.config/zsh, so that is where zsh reads .zshrc,
# .zprofile, .zlogin and .zlogout from. Installers do not know that: they append
# `eval "$(tool init zsh)"` to $HOME/.zshrc, which is now never read. Nothing
# errors -- the tool is simply absent from every shell, and the line that would
# have fixed it sits in a file you have no reason to open.
#
# As silent as a failure gets, and nothing generic can see it: a stray .zshrc is
# a real file rather than a link into the repo, so fs_check_tree misses it, and
# no module ever claimed that path, so the orphan scan misses it too.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

zdotdir="$DOT_CONFIG_HOME/zsh"

# ZDOTDIR is only in the environment when doctor was invoked from a zsh that
# already read ~/.zshenv, so empty means "not observable from here" rather than
# "unset" -- not something to complain about. A value that DISAGREES is: some
# other thing owns the shell, and $HOME/.zshrc is live after all.
if [[ -n ${ZDOTDIR:-} && $ZDOTDIR != "$zdotdir" ]]; then
  warn "zsh          ZDOTDIR is $ZDOTDIR, expected ${zdotdir/#$HOME/\~}"
fi

# `if` rather than a trailing `&&`: a false test on the last iteration leaves
# the loop at status 1, and under set -e that kills the script. See CLAUDE.md.
stray=()
for f in .zshrc .zprofile .zlogin .zlogout; do
  if [[ -e $HOME/$f ]]; then stray+=("$f"); fi
done

if ((${#stray[@]} > 0)); then
  warn "zsh          ~/${stray[0]} exists but zsh reads ${zdotdir/#$HOME/\~} -- something wrote there and it has no effect"
  for f in "${stray[@]:1}"; do
    warn "zsh          ~/$f likewise"
  done
  dim "             move the lines you want into ${zdotdir/#$HOME/\~}/local.zsh, then delete the file"
else
  ok "zsh          no dead config in ~ (ZDOTDIR is ${zdotdir/#$HOME/\~})"
fi
