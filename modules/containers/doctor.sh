#!/usr/bin/env bash
#
# Nothing starts colima for you. A stopped VM makes every docker command fail
# with a connection error that names a socket rather than the reason.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if ! command -v colima >/dev/null 2>&1; then
  fail 'colima       not installed (run: dot apply)'
elif [[ ! -d $HOME/.colima ]]; then
  # `colima status` is NOT read-only: on a machine that never started the VM it
  # creates ~/.colima/_lima before answering. doctor promises to change nothing,
  # so it only asks once there is state to ask about -- and no ~/.colima IS the
  # answer. (remove.sh has the same landmine, for the same reason.)
  warn 'colima       no VM yet (create and start one with: colima start)'
elif colima status >/dev/null 2>&1; then
  ok 'colima       running'
else
  warn 'colima       not running (start it with: colima start)'
fi
