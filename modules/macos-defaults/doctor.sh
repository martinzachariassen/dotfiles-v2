#!/usr/bin/env bash
#
# Verify the settings apply.sh wrote are still in place. This module earns a
# doctor because its failure mode is silent: an OS update or a Settings pane
# can revert a value and nothing announces it. A sample, not an audit -- one
# check per domain, so a wiped plist is caught without a line per write.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# `defaults read` prints booleans as 1/0, hence numbers below, not true/false.
check() {
  local domain=$1 key=$2 want=$3 label=$4 got
  got=$(defaults read "$domain" "$key" 2>/dev/null || echo '<unset>')
  if [[ $got == "$want" ]]; then
    ok "$label"
  else
    warn "$label (expected $want, found $got)"
  fi
}

if module_setting_bool macos-defaults dock_autohide true; then
  want_autohide=1
else
  want_autohide=0
fi

check com.apple.dock autohide "$want_autohide" 'dock autohide'
check com.apple.finder AppleShowAllFiles 1 'finder shows hidden files'
check NSGlobalDomain AppleShowAllExtensions 1 'finder shows extensions'
check NSGlobalDomain ApplePressAndHoldEnabled 0 'key repeat on hold'
check NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled 0 'straight quotes'
check com.apple.WindowManager EnableStandardClickToShowDesktop 0 'wallpaper click'
