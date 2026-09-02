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

@test "get: a value containing a colon survives the YAML round trip" {
  # Everything is read as YAML, and YAML would read `x: y` as a mapping -- so
  # dasel single-quotes it. __cfg_unquote has to take those quotes back off.
  printf 'note = "time: 10:30"\n' >"$DOT_CONFIG"
  run cfg_get 'note'
  [ "$output" = "time: 10:30" ]
}

@test "get: an empty string reads back as empty, not as two quote marks" {
  # The other value YAML cannot render bare: it comes back as the literal "".
  printf 'note = ""\n' >"$DOT_CONFIG"
  run cfg_get 'note' 'fallback'
  [ "$output" = "" ]
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

# --- a config that does not parse whole --------------------------------------
#
# dasel does not validate: it stops at the first malformed line, keeps what it
# read, and exits 0. The old check asked it for `schema`, which the generator
# writes above everything a user edits, so it passed on every truncated config.
# These pin the detector -- and dasel's behaviour, which is what makes the
# detector necessary in the first place.

@test "parse: dasel really does truncate silently -- rc 0, half a document" {
  # If a future dasel starts rejecting this outright, cfg_parse_problems is
  # dead weight and this test is where you find out.
  printf 'schema = 1\n[modules]\nenabled = [ "git" "zsh" ]\n' >"$DOT_CONFIG"
  run dasel -i toml -o yaml 'schema' <"$DOT_CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "parse: a clean config reports no problems" {
  run cfg_parse_problems
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "parse: a missing comma in enabled is caught, not waved through" {
  # The end-to-end scenario. Everything below the typo vanishes, so the config
  # names no modules -- and every link in $HOME is then unclaimed by definition.
  printf 'schema = 1\n[modules]\nenabled = [ "git" "zsh" ]\n\n[settings.git]\nsigningkey = "k"\n' \
    >"$DOT_CONFIG"

  # The trap: nothing else in the engine objects to this file.
  run modules_require_known
  [ "$status" -eq 0 ]
  run cfg_list 'modules.enabled'
  [ -z "$output" ]

  run cfg_parse_problems
  [ -n "$output" ]
  [[ $output == *settings* ]]
}

@test "parse: an empty enabled list is valid, not a parse failure" {
  # The `none` profile writes exactly this, and confusing it with a truncated
  # config would make the detector fire on a supported configuration -- which
  # is the failure mode that gets a check deleted.
  rm "$DOT_CONFIG"
  config_generate "A" "a@b.c" ""

  run cfg_parse_problems
  [ -z "$output" ]
}

@test "parse: a [modules] table whose enabled key was eaten is caught" {
  # The narrow case the table check cannot see on its own: [modules] itself
  # parsed, so it is present in keys(); only the list below it was lost.
  printf 'schema = 1\n[modules]\nenabled = [ "git"\n' >"$DOT_CONFIG"
  run cfg_parse_problems
  [ "$status" -eq 0 ]
  [[ $output == *"no readable"* ]]
}

@test "parse: a dropped table is reported once, by name, with the cause" {
  # Not twice: [settings] going missing must not also trip the enabled check.
  # And the message has to name the table, because "does not parse" over a
  # 40-line file is a message you cannot act on.
  printf 'schema = 1\n[modules]\nenabled = ["git"]\nstray line\n\n[settings.git]\nk = "v"\n' \
    >"$DOT_CONFIG"
  run cfg_parse_problems
  [ "${#lines[@]}" -eq 1 ]
  [[ $output == *"[settings]"* ]]
}

@test "parse: apply refuses a truncated config instead of doing nothing quietly" {
  printf 'schema = 1\n[modules]\nenabled = [ "git" "zsh" ]\n\n[settings.git]\nk = "v"\n' \
    >"$DOT_CONFIG"

  run "$DOT_ROOT/bin/dot" apply --dry-run
  [ "$status" -ne 0 ]
  [[ $output == *"did not parse"* ]]
  # It stopped before deciding the machine needed nothing done to it.
  [[ $output != *"None enabled"* ]]
}

@test "parse: doctor reports it and does not tell you to delete your dotfiles" {
  # The worst consequence, asserted directly. With no enabled modules every
  # link into the repo is an orphan, so doctor listed a working setup under
  # "unclaimed" and closed with `Remove with: rm <path>`.
  printf 'schema = 1\n[modules]\nenabled = [ "git" "zsh" ]\n\n[settings.git]\nk = "v"\n' \
    >"$DOT_CONFIG"

  run bash "$DOT_ROOT/core/doctor.sh"
  [ "$status" -ne 0 ]
  [[ $output == *"cannot see it"* ]]
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

@test "generate: a quote in the git identity does not truncate the config" {
  # No typo required: the wizard offers `git config user.name` as the default,
  # and `Martin "Zach" Z` is a name people have. Written raw it closed the TOML
  # string early, dasel stopped there, and the [modules] table BELOW it was
  # gone from the parsed document -- a first run that enables nothing, from a
  # config the tool wrote itself.
  rm "$DOT_CONFIG"
  config_generate 'Martin "Zach" Z' 'a@b.c' "$(printf 'git\n')"

  run cfg_get 'user.name'
  [ "$output" = 'Martin "Zach" Z' ]
  # The half that vanished.
  run cfg_list 'modules.enabled'
  [ "$output" = "git" ]
  run cfg_parse_problems
  [ -z "$output" ]
}

@test "generate: a backslash survives too, and does not eat the next character" {
  # Backslash has to be escaped BEFORE the quote, or the escape added for a
  # quote gets escaped in turn and the value silently changes shape.
  rm "$DOT_CONFIG"
  config_generate 'back\slash and "quote"' 'a@b.c' ""

  run cfg_get 'user.name'
  [ "$output" = 'back\slash and "quote"' ]
  run cfg_parse_problems
  [ -z "$output" ]
}

@test "generate: dry run writes nothing" {
  rm "$DOT_CONFIG"
  export DOT_DRY_RUN=1
  config_generate "A" "a@b.c" "git"
  [ ! -f "$DOT_CONFIG" ]
}
