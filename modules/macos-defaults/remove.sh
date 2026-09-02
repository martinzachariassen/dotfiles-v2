#!/usr/bin/env bash
#
# There is nothing to undo here, and saying so out loud is the whole job.
#
# apply.sh never read the old values, so they exist nowhere -- not in the repo,
# not in $DOT_STATE, not in macOS. `defaults delete` would not restore them
# either: it drops the key and macOS falls back to Apple's factory value, which
# is a different thing from what you had. Presenting that as a restore is worse
# than doing nothing.
#
# Fixing it properly means apply.sh recording every key before writing it --
# a state file, which this repo does not have on purpose. A trade to make
# deliberately or not at all. Until then: report and stop.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

warn 'macOS preferences were changed and cannot be put back'
dim 'The values from before this repo ran were never recorded. These are the'
dim 'domains it wrote to, if you want to reset keys to Apple defaults by hand:'
dim '  com.apple.dock  com.apple.finder  com.apple.desktopservices'
dim '  com.apple.screencapture  NSGlobalDomain'
