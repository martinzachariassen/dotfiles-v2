#!/usr/bin/env bash
#
# Nothing to undo: apply.sh never read the old values, and `defaults delete`
# would give Apple's factory setting, not what you had. Reversing this needs a
# state file, a trade this repo has not made.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

warn 'macOS preferences were changed and cannot be put back'
dim 'Values from before this repo ran were never recorded. Domains written to:'
dim '  com.apple.dock  com.apple.finder  com.apple.desktopservices'
dim '  com.apple.screencapture  com.apple.WindowManager  NSGlobalDomain'
