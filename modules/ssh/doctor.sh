#!/usr/bin/env bash
#
# Is 1Password's SSH agent actually there?
#
# The tracked half of this module is a link, so fs_check_tree already proves it
# exists and points into the repo. What nothing generic can see is the other
# half, which lives in a GUI: the agent socket only appears once 1Password >
# Settings > Developer > "Use the SSH agent" is ticked. Until then ~/.ssh/config
# names a socket that is not there.
#
# It is worth a check because the failure never mentions ssh config. `git push`
# says "Permission denied (publickey)" and `git commit` on a signing repo says
# "Load key: No such file or directory" -- both of which read as a key problem,
# so you go looking in ~/.ssh, which is empty on purpose and always will be.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Same literal as the IdentityAgent line in home/.ssh/config. THE TWO MUST
# AGREE: if the socket path ever changes, this check goes on passing against
# the old one while ssh reads the new one, which is the one way this hook could
# be worse than no hook at all.
sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

# -S, not -e: an ordinary file at that path means something went wrong in a way
# that -e would call healthy.
if [[ -S $sock ]]; then
  ok 'ssh          1Password agent is live'
else
  warn 'ssh          1Password SSH agent is not running -- keys and signing will fail'
  dim '             enable it: 1Password > Settings > Developer > Use the SSH agent'
fi
