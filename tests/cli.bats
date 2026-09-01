#!/usr/bin/env bats
#
# bin/dot itself: how it reads the command line.
#
# This was the least-tested part of the repo, and it hid the worst kind of bug:
# `dot apply --dry` matched no option, so the mistyped flag was ignored and the
# machine was modified for real. Argument parsing now refuses anything it does
# not recognise, and these tests hold it to that.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

dot() { run "$DOT_ROOT/bin/dot" "$@"; }

@test "cli: no arguments prints the usage" {
  dot
  [ "$status" -eq 0 ]
  [[ $output == *"usage: dot"* ]]
}

@test "cli: an unknown command exits 1 and shows the usage" {
  dot frobnicate
  [ "$status" -eq 1 ]
  [[ $output == *"unknown command frobnicate"* ]]
  [[ $output == *"usage: dot"* ]]
}

@test "apply: a mistyped --dry-run is refused, not ignored" {
  # The regression. `--dry` used to fall through to a real apply.
  dot apply --dry
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--dry'"* ]]
  # And it stopped before phase 1, so nothing was installed on the way out.
  [[ $output != *"Core packages"* ]]
}

@test "apply: --dry-run is accepted and changes nothing" {
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Dry run: nothing was changed."* ]]
  # The clearest evidence a dry run stayed dry: the shim it would have written.
  [ ! -e "$HOME/.local/bin/dot" ]
}

@test "config: an unknown option is refused" {
  dot config --initt
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--initt'"* ]]
}

@test "config: --init refuses to overwrite a config that already exists" {
  config_generate "A" "a@b.c" ""

  dot config --init
  [ "$status" -ne 0 ]
  [[ $output == *"already exists"* ]]
}
