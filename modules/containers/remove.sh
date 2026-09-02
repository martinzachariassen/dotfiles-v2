#!/usr/bin/env bash
#
# Undo apply.sh, plus the one thing the generic sweep structurally cannot see.
#
# uninstall.sh removes symlinks pointing INTO the repo. These point into
# Homebrew's prefix, so no scan filtered on $DOT_ROOT can find them. That gap
# is why remove.sh exists as a hook at all.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Not `die` if Homebrew is missing: by the time you are uninstalling it may
# already be gone, and crashing on that stops the run where stopping helps nobody.
if brew_load; then
  plugin_dir="$(brew --prefix)/lib/docker/cli-plugins"
  for plugin in docker-compose docker-buildx; do
    link="$HOME/.docker/cli-plugins/$plugin"
    # Only the ones pointing where apply.sh pointed them. A link elsewhere was
    # put there by something else -- Docker Desktop, most likely.
    if [[ -L $link && $(readlink "$link") == "$plugin_dir/"* ]]; then
      fs_unlink "$link"
    fi
  done
fi

# Read BEFORE anything invokes colima, and everything below is gated on it:
# `colima status` CREATES ~/.colima on a machine that never had a VM. Asking
# first and testing afterwards made this hook warn about images it had just
# conjured, and made --dry-run write to the disk it promises not to touch.
vm_on_disk=0
if [[ -d $HOME/.colima ]]; then vm_on_disk=1; fi

# Stopped, never deleted. The VM is data: `colima delete` throws away every
# image and volume in it, and stopping is reversible where deleting is not.
if ((vm_on_disk)) && command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
  if [[ $DOT_DRY_RUN == 1 ]]; then
    info 'colima stop'
  else
    colima stop >/dev/null 2>&1 || warn 'colima would not stop; try: colima stop'
  fi
fi

if ((vm_on_disk)); then
  warn 'the colima VM is still on disk, with its images and volumes'
  dim 'Delete it yourself with: colima delete'
fi
