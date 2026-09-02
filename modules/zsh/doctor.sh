#!/usr/bin/env bash
#
# The price of the XDG layout, made loud.
#
# ~/.zshenv points ZDOTDIR at ~/.config/zsh, so that is where zsh reads .zshrc,
# .zprofile, .zlogin and .zlogout from. Installers do not know that. A great
# many of them append `export PATH=...` or `eval "$(tool init zsh)"` to
# $HOME/.zshrc without looking, and with ZDOTDIR set, that file is never read
# again. Nothing errors. The tool is simply absent from every shell, and the
# line that would have fixed it sits in a file you have no reason to open.
#
# That is the entire reason this hook exists. A check earns its place only if
# the thing it checks fails silently, and this is as silent as it gets:
# fs_check_tree cannot see it (a stray .zshrc is a real file, not a link into
# the repo) and neither can the orphan scan (nothing in modules/ ever claimed
# that path).

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

zdotdir="$DOT_CONFIG_HOME/zsh"

# Checked first because it decides whether the loop below is right or exactly
# backwards. ZDOTDIR is only in the environment when doctor was invoked from a
# zsh that already read ~/.zshenv -- an empty value means "not observable from
# here", not "unset", so it is not something to complain about. A value that
# disagrees is: some other thing owns the shell, and $HOME/.zshrc is live.
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
