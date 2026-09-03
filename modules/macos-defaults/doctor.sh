#!/usr/bin/env bash
#
# An OS update or a Settings pane can revert a value silently. A sample, not
# an audit: one check per domain catches a wiped plist.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# `defaults read` prints booleans as 1/0.
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
