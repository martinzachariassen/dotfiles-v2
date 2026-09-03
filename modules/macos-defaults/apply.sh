#!/usr/bin/env bash
#
# macOS preferences. Imperative and idempotent; nothing needs root. Overrides
# live under [settings.macos-defaults]. Trailing comments name what an opaque
# key does.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'write macOS defaults (Dock, Finder, keyboard) and restart those apps'
  exit 0
fi

# --- Dock -------------------------------------------------------------------
# Normalised to a literal true/false; doctor.sh reads the setting the same way.
if module_setting_bool macos-defaults dock_autohide true; then
  dock_autohide=true
else
  dock_autohide=false
fi
defaults write com.apple.dock autohide -bool "$dock_autohide"
defaults write com.apple.dock autohide-delay -float 0         # no reveal wait
defaults write com.apple.dock autohide-time-modifier -float 0 # no slide-in
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock mru-spaces -bool false # ctrl-N is stable

# `defaults -int` stores non-numeric as 0, and tilesize 0 is a Dock with no
# icons. fail, not die: one bad field must not cost the rest.
tilesize=$(module_setting macos-defaults dock_tilesize 48)
if [[ $tilesize =~ ^[0-9]+$ ]] && ((tilesize > 0)); then
  defaults write com.apple.dock tilesize -int "$tilesize"
else
  fail "dock_tilesize '$tilesize' is not a positive number -- left as it was"
fi

# --- Finder -----------------------------------------------------------------
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder FXPreferredViewStyle -string 'Nlsv' # list view
defaults write com.apple.finder FXDefaultSearchScope -string 'SCcf' # current folder
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
# .DS_Store only on local disks, not on shares and USB sticks.
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# --- Keyboard ---------------------------------------------------------------
# Repeat values are 1/60s ticks; both are the System Settings floor.
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false # repeat, not accents
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3 # Tab reaches buttons

# --- Text substitution ------------------------------------------------------
# Curly quotes and em dashes break every snippet pasted into chat.
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# --- Documents and windows --------------------------------------------------
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false # wallpaper click
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true         # full save sheet
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

# --- Screenshots ------------------------------------------------------------
# Relative to $HOME unless absolute; a leading ~ is expanded, not taken literally.
screenshot_dir=$(module_setting macos-defaults screenshot_dir 'Pictures/Screenshots')
screenshot_dir=${screenshot_dir/#\~\//$HOME/}
[[ $screenshot_dir == /* ]] || screenshot_dir="$HOME/$screenshot_dir"
mkdir -p "$screenshot_dir"
defaults write com.apple.screencapture location -string "$screenshot_dir"
defaults write com.apple.screencapture disable-shadow -bool true

# --- Apply ------------------------------------------------------------------
# These read preferences at launch only. NSGlobalDomain needs a re-login.
for app in Dock Finder SystemUIServer WindowManager; do
  killall "$app" >/dev/null 2>&1 || true
done

ok 'macOS defaults written'
warn 'log out and back in for keyboard and text-substitution changes to fully apply'
