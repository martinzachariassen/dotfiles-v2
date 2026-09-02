#!/usr/bin/env bash
#
# macOS system preferences. No Brewfile, no home/ tree -- purely imperative,
# and `defaults write` is idempotent, so re-running is free. Nothing here needs
# root: every domain is a per-user plist, the screenshot dir is under $HOME,
# killall signals only your own processes. Overrides live in config.toml under
# [settings.macos-defaults].
#
# Trailing comments, against house style: these keys are opaque -- SCcf, Nlsv,
# mru-spaces -- so each write says what it does. Block comments are landmines.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'write macOS defaults (Dock, Finder, keyboard) and restart those apps'
  exit 0
fi

# --- Dock -------------------------------------------------------------------
# Normalised to a literal true/false: `defaults` rejects anything else, and
# doctor.sh reads the setting the same way, so the two cannot disagree.
if module_setting_bool macos-defaults dock_autohide true; then
  dock_autohide=true
else
  dock_autohide=false
fi
defaults write com.apple.dock autohide -bool "$dock_autohide"
defaults write com.apple.dock autohide-delay -float 0         # no reveal wait
defaults write com.apple.dock autohide-time-modifier -float 0 # no slide-in
defaults write com.apple.dock show-recents -bool false        # no recents
defaults write com.apple.dock mru-spaces -bool false          # ctrl-N is stable

# Icon size in points; Apple ships 64. `defaults -int` does not validate: it
# stores non-numeric as 0, and a tilesize of 0 is a Dock whose icons have no
# width. fail, not die, so one bad field does not cost you everything below.
tilesize=$(module_setting macos-defaults dock_tilesize 48)
if [[ $tilesize =~ ^[0-9]+$ ]] && ((tilesize > 0)); then
  defaults write com.apple.dock tilesize -int "$tilesize"
else
  fail "dock_tilesize '$tilesize' is not a positive number -- left as it was"
fi

# --- Finder -----------------------------------------------------------------
# Undocumented codes: view style Nlsv list, icnv icon, clmv column, Flwv
# gallery; search scope SCcf current folder, SCev this Mac (Apple's default).
defaults write com.apple.finder AppleShowAllFiles -bool true   # dotfiles
defaults write com.apple.finder ShowPathbar -bool true         # path crumbs
defaults write com.apple.finder ShowStatusBar -bool true       # count + free
defaults write com.apple.finder _FXSortFoldersFirst -bool true # dirs on top
defaults write com.apple.finder FXPreferredViewStyle -string 'Nlsv'
defaults write com.apple.finder FXDefaultSearchScope -string 'SCcf'
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write NSGlobalDomain AppleShowAllExtensions -bool true # index.ts|tsx
# No .DS_Store on volumes Finder does not own: on a share they land in other
# people's diffs. Local disks still get them -- there the view data is wanted.
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# --- Keyboard ---------------------------------------------------------------
# Repeat values are 1/60s ticks, and both are the System Settings floor:
# ~33ms per character, ~250ms before repeating starts.
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false # not accents
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3 # Tab reaches buttons

# --- Text substitution ------------------------------------------------------
# System-wide: Notes, Mail and Slack, but not a real editor -- so they go
# unnoticed until a snippet pasted into chat stops parsing. Curly quotes and em
# dashes are characters no shell or compiler accepts.
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# --- Documents and windows --------------------------------------------------
# Sonoma made a stray click on a sliver of wallpaper hide every open window.
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true # full sheet
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false # disk

# --- Screenshots ------------------------------------------------------------
# Relative to $HOME unless the value already says otherwise. Prefixing blindly
# filed absolute paths under $HOME/Users/... and a leading ~ under a directory
# named "~" -- created silently, and not where you would look for a screenshot.
screenshot_dir=$(module_setting macos-defaults screenshot_dir 'Pictures/Screenshots')
screenshot_dir=${screenshot_dir/#\~\//$HOME/}
[[ $screenshot_dir == /* ]] || screenshot_dir="$HOME/$screenshot_dir"
mkdir -p "$screenshot_dir"
defaults write com.apple.screencapture location -string "$screenshot_dir"
defaults write com.apple.screencapture disable-shadow -bool true # ~100px padding

# --- Apply ------------------------------------------------------------------
# These read preferences at launch only; NSGlobalDomain cannot be flushed this
# way at all, hence the warn below. `|| true`: killall exits 1 when a process
# is not running, which is not a failure.
for app in Dock Finder SystemUIServer WindowManager; do
  killall "$app" >/dev/null 2>&1 || true
done

ok 'macOS defaults written'
warn 'log out and back in for keyboard and text-substitution changes to fully apply'
