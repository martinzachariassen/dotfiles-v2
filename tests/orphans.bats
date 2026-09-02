#!/usr/bin/env bats
#
# fs_orphans once shipped with no test at all, and a runtime-only bug rode
# along with it while CI stayed green. These pin the behaviour: what counts as
# an orphan, and just as importantly what does not.

setup() {
  load helper
  setup_sandbox

  # A repo root inside the sandbox, so "points into the repo" is controllable
  # and no test depends on the real checkout.
  REPO="$DOT_TMP/repo"
  MODULE="$REPO/modules/demo"
  mkdir -p "$MODULE/home/.config/demo"
  # The manifest is what makes the module visible to the registry, and
  # fs_orphans now takes its scan roots from there rather than from whatever
  # is enabled. Without it the fixture is a directory the repo does not know.
  printf 'description = "demo"\n' >"$MODULE/module.toml"
  DOT_ROOT="$REPO"
}

teardown() { teardown_sandbox; }

# Everything below claims exactly one file: ~/.config/demo/kept.conf
claim_one() {
  printf 'content\n' >"$MODULE/home/.config/demo/kept.conf"
  modules_enabled_dirs() { printf '%s\n' "$MODULE"; }
  fs_link_tree "$MODULE"
}

@test "orphans: a clean tree reports nothing" {
  claim_one
  run fs_orphans
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "orphans: a link into the repo that no module claims is reported" {
  claim_one
  ln -s "$MODULE/home/.config/demo/deleted.conf" "$HOME/.config/demo/stale.conf"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *stale.conf* ]]
  [[ $output != *kept.conf* ]]
}

@test "orphans: a link pointing outside the repo is left alone" {
  claim_one
  printf 'x\n' >"$DOT_TMP/elsewhere.txt"
  ln -s "$DOT_TMP/elsewhere.txt" "$HOME/.config/demo/foreign.conf"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *foreign.conf* ]]
}

@test "orphans: a real file is not a link and is never reported" {
  claim_one
  printf 'x\n' >"$HOME/.config/demo/notes.txt"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *notes.txt* ]]
}

@test "orphans: nothing enabled is not an error" {
  modules_enabled_dirs() { :; }
  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *"invalid option"* ]]
}

@test "orphans: a link left behind by a DISABLED module is reported" {
  # The case this function exists for, and the one it used to miss entirely.
  # Scan roots were derived from the ENABLED modules, so switching a module off
  # removed its directory from the scan and every link it had left behind
  # became invisible -- `dot doctor` printed "none" over a home directory still
  # full of them, which is the one situation where the report matters.
  claim_one
  modules_enabled_dirs() { :; } # the module is now disabled in the config

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *kept.conf* ]]
}

@test "orphans: a disabled module does not claim its files back" {
  # The other half of the same fix: a disabled module still contributes where
  # to look, but it must not contribute what counts as claimed -- otherwise
  # widening the scan would quietly hide every orphan it just exposed.
  claim_one
  modules_enabled_dirs() { :; }

  run fs_orphans
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
