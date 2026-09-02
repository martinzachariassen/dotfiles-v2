#!/usr/bin/env bash
#
# There is nothing to undo here, and saying so out loud is the whole job.
#
# apply.sh writes system preferences with `defaults write`. It never read what
# was there first, so the previous values exist nowhere -- not in this repo,
# not in $DOT_STATE, not in macOS. `defaults delete` would not restore them
# either: it drops the key and lets macOS fall back to Apple's factory value,
# which is a different thing from what you had, and quietly presenting it as a
# restore is worse than doing nothing.
#
# The real fix is not in this file. It is in apply.sh, which would have to read
# every key before writing it and store the result -- and that means a state
# file recording what the last run did, which this repo does not have on
# purpose (CLAUDE.md, "the tool writes the config exactly once"). That is a
# trade worth making deliberately or not at all. Until then: report and stop.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

warn 'macOS preferences were changed and cannot be put back'
dim 'The values from before this repo ran were never recorded. These are the'
dim 'domains it wrote to, if you want to reset keys to Apple defaults by hand:'
dim '  com.apple.dock  com.apple.finder  com.apple.desktopservices'
dim '  com.apple.screencapture  NSGlobalDomain'
