#!/usr/bin/env bash
#
# Nothing starts colima for you. A stopped VM makes every docker command fail
# with a connection error that names a socket rather than the reason.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if command -v colima >/dev/null 2>&1; then
  if colima status >/dev/null 2>&1; then
    ok 'colima       running'
  else
    warn 'colima       not running (start it with: colima start)'
  fi
else
  fail 'colima       not installed (run: dot apply)'
fi
