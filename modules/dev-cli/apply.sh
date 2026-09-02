#!/usr/bin/env bash
#
# `mise activate` only rewrites PATH for versions already on disk -- it never
# installs one, and the shell hook does not run at apply time anyway. Without
# this, home/.config/mise/config.toml sits there linked and unread until
# someone remembers to run `mise install` by hand.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'mise install (runtimes pinned in ~/.config/mise/config.toml)'
  exit 0
fi

mise install --yes
ok 'mise: runtimes installed'
