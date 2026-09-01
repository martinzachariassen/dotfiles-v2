#!/usr/bin/env bash
#
# Verify the settings apply.sh wrote are still in place.
#
# This module needs a doctor precisely because its failure mode is silent: a
# macOS update, a Settings pane, or another tool can quietly revert a value
# and nothing announces it. Compare that to a missing symlink, which you find
# out about the moment you use the thing.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# check DOMAIN KEY EXPECTED LABEL
check() {
  local domain=$1 key=$2 want=$3 label=$4 got
  got=$(defaults read "$domain" "$key" 2>/dev/null || echo '<unset>')
  if [[ $got == "$want" ]]; then
    ok "$label"
  else
    warn "$label (expected $want, found $got)"
  fi
}

want_autohide=$(module_setting_bool macos-defaults dock_autohide true && echo 1 || echo 0)

check com.apple.dock autohide "$want_autohide" 'dock autohide'
check com.apple.dock show-recents 0 'dock hides recents'
check com.apple.finder ShowPathbar 1 'finder path bar'
check com.apple.finder AppleShowAllFiles 1 'finder shows hidden files'
check NSGlobalDomain ApplePressAndHoldEnabled 0 'key repeat on hold'
