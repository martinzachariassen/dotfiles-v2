#!/usr/bin/env bash
#
# `mise activate` never installs a runtime; linking config.toml alone leaves it
# unread until someone runs `mise install` by hand.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'mise install (runtimes pinned in ~/.config/mise/config.toml)'
  exit 0
fi

mise install --yes
ok 'mise: runtimes installed'
