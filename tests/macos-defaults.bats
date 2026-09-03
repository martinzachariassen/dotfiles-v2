#!/usr/bin/env bats
#
# modules/macos-defaults/apply.sh. `defaults` is shadowed on PATH: it talks to
# cfprefsd, which ignores $HOME, so the real one would rewrite the developer's
# settings. The stub records every call and doubles as the assertion.

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
  [ "$status" -eq "$DOT_STATUS_WARN" ] # the logout reminder always warns
  wrote 'com.apple.dock tilesize -int 64'
}

@test "tilesize: garbage is refused instead of silently becoming 0" {
  # `defaults write ... -int big` exits 0 and stores 0: a Dock with no icons.
  with_settings 'dock_tilesize = "big"'
  apply
  [ "$status" -ne 0 ]
  [[ $output == *"dock_tilesize"* ]]
  # Refusing must mean the old value survives.
  run grep -c 'tilesize' "$CALLS"
  [ "$output" = "0" ]
}

@test "tilesize: 0 is refused as well" {
  with_settings 'dock_tilesize = 0'
  apply
  [ "$status" -ne 0 ]
  [[ $output == *"dock_tilesize"* ]]
}

@test "tilesize: one bad field does not cost you the rest of the module" {
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
  [ "$status" -eq "$DOT_STATUS_WARN" ] # the logout reminder always warns
  wrote "com.apple.screencapture location -string $HOME/Pictures/Shots"
  [ -d "$HOME/Pictures/Shots" ]
}

@test "screenshots: an absolute path is used as given, not nested under \$HOME" {
  with_settings "screenshot_dir = \"$DOT_TMP/shots\""
  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ] # the logout reminder always warns
  wrote "com.apple.screencapture location -string $DOT_TMP/shots"
  [ ! -d "$HOME$DOT_TMP" ]
}

@test "screenshots: a leading ~ is expanded, not taken literally" {
  # A tilde in a TOML string is just a character.
  with_settings 'screenshot_dir = "~/Shots"'
  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ] # the logout reminder always warns
  wrote "com.apple.screencapture location -string $HOME/Shots"
  [ ! -e "$HOME/~" ]
}

@test "screenshots: the default lands in Pictures/Screenshots" {
  with_settings '# nothing set'
  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ] # the logout reminder always warns
  wrote "com.apple.screencapture location -string $HOME/Pictures/Screenshots"
}

# --- dry run --------------------------------------------------------------------

@test "dry run: describes the writes and makes none" {
  with_settings 'dock_tilesize = 64'
  local before
  before=$(home_snapshot)

  apply 1
  [ "$status" -eq 0 ]
  [[ $output == *"write macOS defaults"* ]]
  [ ! -f "$CALLS" ]
  [ "$(home_snapshot)" = "$before" ]
}
