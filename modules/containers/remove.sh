#!/usr/bin/env bash
#
# Undo apply.sh, plus the one thing the generic sweep structurally cannot see.
#
# uninstall.sh removes symlinks that point INTO the repo. These point into
# Homebrew's prefix instead -- apply.sh used fs_link for them because that
# function is careful, not because the repo owns their targets -- so no scan
# filtered on $DOT_ROOT will ever find them. This is the gap that justifies
# remove.sh existing as a hook at all.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Not `die` if Homebrew is missing: by the time you are uninstalling, brew may
# already be gone, and a hook that crashes on that would stop the run at the
# exact point where stopping helps nobody.
if brew_load; then
  plugin_dir="$(brew --prefix)/lib/docker/cli-plugins"
  for plugin in docker-compose docker-buildx; do
    link="$HOME/.docker/cli-plugins/$plugin"
    # Only the ones pointing where apply.sh pointed them. A link to somewhere
    # else was put there by something else -- Docker Desktop, most likely --
    # and this repo does not get to guess on its behalf.
    if [[ -L $link && $(readlink "$link") == "$plugin_dir/"* ]]; then
      fs_unlink "$link"
    fi
  done
fi

# Read BEFORE anything invokes colima, and everything below is gated on it.
# `colima status` creates ~/.colima on a machine that never had a VM, so asking
# first and testing afterwards made this hook warn about images and volumes it
# had just conjured -- and made --dry-run write to the disk it promises not to
# touch. No ~/.colima means there is no VM to stop and none to warn about.
vm_on_disk=0
if [[ -d $HOME/.colima ]]; then vm_on_disk=1; fi

# The VM is data, not configuration. `colima delete` throws away every image
# and volume in it, and that is not a call an uninstaller should make for you.
# Stopping it is reversible; deleting it is not.
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
