#!/usr/bin/env bats
#
# Config reading, and the one generator.
#
# Several of these pin down dasel v3 behaviour that is genuinely surprising --
# if a future dasel changes it, these tests are how you find out.

load helper

setup() {
  setup_sandbox
  cat >"$DOT_CONFIG" <<'EOF'
schema = 1

[user]
name  = "Martin Zachariassen"
email = "m@example.com"

[modules]
enabled = ["git", "zsh"]

[settings.git]
signingkey = "ssh-ed25519 AAAA"

[settings.macos-defaults]
dock_autohide = false
dock_tilesize = 64
EOF
}
teardown() { teardown_sandbox; }

@test "get: reads a scalar without quotes" {
  run cfg_get 'user.name'
  [ "$output" = "Martin Zachariassen" ]
}

@test "get: falls back to the default for a missing key" {
  run cfg_get 'user.nickname' 'none'
  [ "$output" = "none" ]
}

@test "get: an absent config file yields the default, not an error" {
  rm "$DOT_CONFIG"
  run cfg_get 'user.name' 'fallback'
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "list: reads an array one element per line" {
  run cfg_list 'modules.enabled'
  [ "${lines[0]}" = "git" ]
  [ "${lines[1]}" = "zsh" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "list: an empty array yields nothing" {
  printf 'x = []\n' >"$DOT_CONFIG"
  run cfg_list 'x'
  [ -z "$output" ]
}

@test "setting: reads a dashed module name via bracket syntax" {
  # dasel parses settings.macos-defaults.x as a subtraction. If this test
  # fails, module_setting stopped escaping and every dashed module broke.
  run module_setting macos-defaults dock_tilesize
  [ "$output" = "64" ]
}

@test "setting: bool is true only for the literal true" {
  run module_setting_bool macos-defaults dock_autohide true
  [ "$status" -eq 1 ]
  run module_setting_bool macos-defaults nothing_here true
  [ "$status" -eq 0 ]
}

@test "setting: undefined module setting returns the default" {
  run module_setting git nonexistent 'fallback'
  [ "$output" = "fallback" ]
}

# --- the generator ----------------------------------------------------------

@test "generate: refuses to overwrite an existing config" {
  run config_generate "A" "a@b.c" "git"
  [ "$status" -ne 0 ]
  # the original survives untouched
  run cfg_get 'user.name'
  [ "$output" = "Martin Zachariassen" ]
}

@test "generate: writes a file that reads back correctly" {
  rm "$DOT_CONFIG"
  config_generate "Ada Lovelace" "ada@example.com" "$(printf 'git\nzsh\n')"

  run cfg_get 'user.name'
  [ "$output" = "Ada Lovelace" ]
  run cfg_get 'user.email'
  [ "$output" = "ada@example.com" ]
  run cfg_list 'modules.enabled'
  [ "${#lines[@]}" -eq 2 ]
}

@test "generate: the result keeps its comments" {
  # The entire reason the tool writes only once.
  rm "$DOT_CONFIG"
  config_generate "A" "a@b.c" "git"
  run grep -c '^#' "$DOT_CONFIG"
  [ "$output" -gt 3 ]
}

@test "generate: dry run writes nothing" {
  rm "$DOT_CONFIG"
  export DOT_DRY_RUN=1
  config_generate "A" "a@b.c" "git"
  [ ! -f "$DOT_CONFIG" ]
}
