#!/usr/bin/env bash
#
# There is nothing to undo here, and saying so out loud is the whole job.
# apply.sh never read the old values, so they exist nowhere. `defaults delete`
# would not restore them either: it drops the key and macOS falls back to a
# factory value, a different thing from what you had. Doing it properly needs a
# state file, which this repo does not have on purpose.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

warn 'macOS preferences were changed and cannot be put back'
dim 'Values from before this repo ran were never recorded. Domains written to:'
dim '  com.apple.dock  com.apple.finder  com.apple.desktopservices'
dim '  com.apple.screencapture  com.apple.WindowManager  NSGlobalDomain'
