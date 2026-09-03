#!/usr/bin/env bats
#
# lib/brew.sh. Nothing installs anything: brew_load and brew are stubbed.

setup() {
  load helper
  setup_sandbox
}

teardown() { teardown_sandbox; }

@test "bundle: a module with no Brewfile is success, not failure" {
  # A 1 here makes module_apply skip apply.sh with no error message.
  run brew_bundle "$DOT_TMP/nope/Brewfile" demo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bundle: the missing-file check comes before the Homebrew check" {
  brew_load() { return 1; }

  run brew_bundle "$DOT_TMP/nope/Brewfile" demo
  [ "$status" -eq 0 ]
  [[ $output != *Homebrew* ]]
}

@test "bundle: a real Brewfile with no Homebrew fails and says which module" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 1; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  [[ $output == *"Homebrew is not installed"* ]]
  [[ $output == *demo* ]]
}

@test "bundle: a dry run announces the file and installs nothing" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { printf 'BREW-WAS-CALLED\n'; }
  export DOT_DRY_RUN=1

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 0 ]
  [[ $output != *BREW-WAS-CALLED* ]]
  [[ $output == *"brew bundle"* ]]
}

@test "bundle: the label defaults to the module directory name" {
  # $label must be a separate `local`: merged with $file, the default expands
  # before $file is assigned (SC2318) and the name is silently empty.
  mkdir -p "$DOT_TMP/modules/widgets"
  printf 'brew "jq"\n' >"$DOT_TMP/modules/widgets/Brewfile"
  brew_load() { return 1; }

  run brew_bundle "$DOT_TMP/modules/widgets/Brewfile"
  [ "$status" -eq 1 ]
  [[ $output == *widgets* ]]
}

@test "bundle: a failing brew bundle is reported against the module" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { return 1; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  [[ $output == *"brew bundle failed for demo"* ]]
}

@test "bundle: --no-upgrade is passed, so apply never bumps a version" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { printf '%s\n' "$*"; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 0 ]
  [[ $output == *"--no-upgrade"* ]]
}
