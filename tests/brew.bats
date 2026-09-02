#!/usr/bin/env bats
#
# lib/brew.sh.
#
# Every other test file stubs brew_bundle out, so the real one was never run
# by anything. That is a bad place to have no coverage: module_apply reads its
# return value to decide whether to run apply.sh at all, so a wrong answer here
# does not fail loudly -- it silently skips the imperative half of a module.
#
# Nothing here installs anything. brew_load is stubbed where a real Homebrew
# would otherwise be consulted, so the tests say the same thing on a machine
# that has never had it.

setup() {
  load helper
  setup_sandbox
}

teardown() { teardown_sandbox; }

@test "bundle: a module with no Brewfile is success, not failure" {
  # "This module has no packages" is a normal thing to be. If this returned 1,
  # module_apply would mark the module unpackaged and skip its apply.sh --
  # which is exactly the failure that produces no error message.
  run brew_bundle "$DOT_TMP/nope/Brewfile" demo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bundle: the missing-file check comes before the Homebrew check" {
  # Order matters on a machine without brew: a module that ships no Brewfile
  # needs nothing from Homebrew, so it must not be dragged down by its absence.
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
  # If the dry-run branch ever moved below the install, this stub is what
  # catches it: a dry run that reaches `brew` is the bug.
  brew() { printf 'BREW-WAS-CALLED\n'; }
  export DOT_DRY_RUN=1

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 0 ]
  [[ $output != *BREW-WAS-CALLED* ]]
  [[ $output == *"brew bundle"* ]]
}

@test "bundle: the label defaults to the module directory name" {
  # $label is a separate `local` statement because $file is not yet assigned
  # while the default is being expanded (shellcheck SC2318). Merged into one
  # `local`, the name silently becomes empty and every failure reads
  # "cannot install packages for ".
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
  # An apply that upgraded packages would make every run a different run.
  # Upgrading is `brew upgrade`, a thing you choose to do.
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { printf '%s\n' "$*"; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 0 ]
  [[ $output == *"--no-upgrade"* ]]
}
