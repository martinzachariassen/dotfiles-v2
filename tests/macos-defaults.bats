#!/usr/bin/env bats
#
# modules/macos-defaults/apply.sh -- the two values it derives from config.
#
# Everything here runs against a stub `defaults` on PATH, and that is not a
# convenience. `defaults` talks to cfprefsd, which does not care what $HOME
# says, so a test that let the real one through would rewrite the developer's
# Dock and Finder settings every time the suite ran. Shadowing the command is a
# stronger guarantee than trusting the module's own --dry-run branch: PATH
# resolution holds whether or not the code under test is correct, which is the
# property you want from the thing standing between a test and your machine.
#
# The stub doubles as the assertion -- it records every call, so these tests ask
# what the module TRIED to write rather than what the machine ended up with.

load helper

setup() {
  setup_sandbox

  BIN="$DOT_TMP/bin"
  CALLS="$DOT_TMP/defaults-calls"
  mkdir -p "$BIN"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s"\n' "$CALLS" >"$BIN/defaults"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/killall"
  chmod +x "$BIN/defaults" "$BIN/killall"
}

teardown() { teardown_sandbox; }

# with_settings BODY -- a config whose [settings.macos-defaults] table is BODY.
with_settings() {
  printf 'schema = 1\n\n[modules]\nenabled = ["macos-defaults"]\n\n[settings.macos-defaults]\n%s\n' \
    "$1" >"$DOT_CONFIG"
}

apply() {
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    "$BASH" "$DOT_ROOT/modules/macos-defaults/apply.sh"
}

wrote() { grep -qF "$1" "$CALLS"; }

# --- dock_tilesize -------------------------------------------------------------

@test "tilesize: a number is passed through" {
  with_settings 'dock_tilesize = 64'
  apply
  [ "$status" -eq 0 ]
  wrote 'com.apple.dock tilesize -int 64'
}

@test "tilesize: garbage is refused instead of silently becoming 0" {
  # `defaults write ... -int big` exits 0 and stores 0, and a tilesize of 0 is a
  # Dock whose icons have no width -- so the only report you get is that your
  # Dock disappeared, with the config still reading `dock_tilesize = "big"`.
  with_settings 'dock_tilesize = "big"'
  apply
  [ "$status" -ne 0 ]
  [[ $output == *"dock_tilesize"* ]]
  # Not written at all: refusing has to mean the old value survives, or this is
  # a louder version of the same bug.
  run grep -c 'tilesize' "$CALLS"
  [ "$output" = "0" ]
}

@test "tilesize: 0 is refused as well" {
  # The value garbage decays into, so a check that only tested for digits would
  # wave through the one number that does the damage.
  with_settings 'dock_tilesize = 0'
  apply
  [ "$status" -ne 0 ]
  [[ $output == *"dock_tilesize"* ]]
}

@test "tilesize: one bad field does not cost you the rest of the module" {
  # Why it is a fail and not a die. The Finder and keyboard settings have
  # nothing to do with the Dock, and losing them to a typo three lines above
  # would make the module's behaviour depend on the order its writes happen to
  # be in.
  with_settings 'dock_tilesize = "big"'
  apply
  [ "$status" -ne 0 ]
  wrote 'com.apple.finder ShowPathbar -bool true'
  wrote 'NSGlobalDomain KeyRepeat -int 2'
}

# --- screenshot_dir ------------------------------------------------------------

@test "screenshots: a relative path is taken from \$HOME" {
  with_settings 'screenshot_dir = "Pictures/Shots"'
  apply
  [ "$status" -eq 0 ]
  wrote "com.apple.screencapture location -string $HOME/Pictures/Shots"
  [ -d "$HOME/Pictures/Shots" ]
}

@test "screenshots: an absolute path is used as given, not nested under \$HOME" {
  # It used to be prefixed unconditionally, so /Volumes/ext/Shots became
  # \$HOME/Volumes/ext/Shots -- created without complaint, and screenshots then
  # went somewhere the user had no reason to look.
  with_settings "screenshot_dir = \"$DOT_TMP/shots\""
  apply
  [ "$status" -eq 0 ]
  wrote "com.apple.screencapture location -string $DOT_TMP/shots"
  [ ! -d "$HOME$DOT_TMP" ]
}

@test "screenshots: a leading ~ is expanded, not taken literally" {
  # A tilde in a TOML string is just a character; nothing expands it on the way
  # in. Unhandled, this made a directory whose name was "~".
  with_settings 'screenshot_dir = "~/Shots"'
  apply
  [ "$status" -eq 0 ]
  wrote "com.apple.screencapture location -string $HOME/Shots"
  [ ! -e "$HOME/~" ]
}

@test "screenshots: the default lands in Pictures/Screenshots" {
  with_settings '# nothing set'
  apply
  [ "$status" -eq 0 ]
  wrote "com.apple.screencapture location -string $HOME/Pictures/Screenshots"
}

# --- dry run --------------------------------------------------------------------

@test "dry run: describes the writes and makes none" {
  # The guard is first in the file, so this also proves nothing above it reads
  # config or touches the disk on the way to that check.
  with_settings 'dock_tilesize = 64'
  local before
  before=$(home_snapshot)

  apply 1
  [ "$status" -eq 0 ]
  [[ $output == *"write macOS defaults"* ]]
  [ ! -f "$CALLS" ]
  [ "$(home_snapshot)" = "$before" ]
}
