#!/usr/bin/env bash
#
# Two things about a colima setup fail quietly enough to be worth a check.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

plugins="$HOME/.docker/cli-plugins"

# --- Leftovers from Docker Desktop ------------------------------------------
# Uninstalling Docker Desktop leaves one symlink per plugin behind, pointing
# into a /Applications/Docker.app that no longer exists. The docker CLI skips
# them without saying so, so `docker scout` is simply "unknown command" with no
# hint that a broken link is why.
#
# Reported, never removed: an apply in this repo does not delete things from
# your home directory, and the same rule holds for a doctor that only reads.
if [[ -d $plugins ]]; then
  dangling=0
  # `if`, not `[[ ... ]] && count++`: a false test on the last iteration would
  # leave the loop at status 1 and errexit would kill the script. See CLAUDE.md.
  for link in "$plugins"/*; do
    if [[ -L $link && ! -e $link ]]; then
      dangling=$((dangling + 1))
    fi
  done
  if ((dangling)); then
    warn "cli-plugins  $dangling dead link(s) in ~/.docker/cli-plugins"
    dim "Remove with: find ~/.docker/cli-plugins -type l ! -exec test -e {} \\; -delete"
  else
    ok 'cli-plugins  no dead links'
  fi
fi

# --- The VM -----------------------------------------------------------------
# Nothing starts colima for you. A stopped VM makes every docker command fail
# with a connection error that names a socket rather than the reason.
if command -v colima >/dev/null 2>&1; then
  if colima status >/dev/null 2>&1; then
    ok 'colima       running'
  else
    warn 'colima       not running (start it with: colima start)'
  fi
else
  fail 'colima       not installed (run: dot apply)'
fi
