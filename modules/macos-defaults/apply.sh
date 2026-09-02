#!/usr/bin/env bash
#
# macOS system preferences.
#
# The module that proves everything except module.toml is optional: no
# Brewfile, no home/ tree, purely imperative. `defaults write` is naturally
# idempotent, so re-running is free.
#
# Every value here can be overridden from config.toml under
# [settings.macos-defaults]; the defaults below are what you get if you say
# nothing.
#
# Nothing here needs root, despite the name -- "system preferences" describes
# what they affect, not where they live. Every domain written below is a
# per-user plist in ~/Library/Preferences, the screenshot directory is under
# $HOME, and killall only signals your own processes. This module used to
# declare `sudo = true` and so primed an administrator prompt on every apply
# that no command below ever spent; it was the last claim on that manifest
# field, and the field went with it.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'write macOS defaults (Dock, Finder, keyboard) and restart those apps'
  exit 0
fi

# --- Dock -------------------------------------------------------------------
# Normalised to a literal true/false rather than passed through: `defaults`
# rejects anything else, and doctor.sh compares against the same reading of
# the setting, so the two can never disagree about what was asked for.
if module_setting_bool macos-defaults dock_autohide true; then
  dock_autohide=true
else
  dock_autohide=false
fi
defaults write com.apple.dock autohide -bool "$dock_autohide"
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock tilesize -int \
  "$(module_setting macos-defaults dock_tilesize 48)"

# --- Finder -----------------------------------------------------------------
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string 'Nlsv'
defaults write com.apple.finder _FXSortFoldersFirst -bool true
# Search the current folder rather than the whole Mac.
defaults write com.apple.finder FXDefaultSearchScope -string 'SCcf'
# No .DS_Store on network or USB volumes.
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# --- Keyboard ---------------------------------------------------------------
# Key repeat instead of the accent picker on press-and-hold.
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# --- Screenshots ------------------------------------------------------------
screenshot_dir="${HOME}/$(module_setting macos-defaults screenshot_dir 'Pictures/Screenshots')"
mkdir -p "$screenshot_dir"
defaults write com.apple.screencapture location -string "$screenshot_dir"
defaults write com.apple.screencapture disable-shadow -bool true

# --- Apply ------------------------------------------------------------------
# These read their preferences at launch, so they have to be restarted.
for app in Dock Finder SystemUIServer; do
  killall "$app" >/dev/null 2>&1 || true
done

ok 'macOS defaults written (some changes need a logout to appear everywhere)'
