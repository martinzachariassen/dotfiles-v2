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
  # claim_one first, deliberately. Without it $HOME/.config/demo does not
  # exist, the output is empty whatever the code does, and the assertion below
  # is checking nothing -- which is how this test used to be written.
  claim_one
  modules_enabled_dirs() { :; }

  run fs_orphans
  [ "$status" -eq 0 ]
  # An empty claimed map must still produce a clean scan, not a bash error
  # about an unset associative array.
  [[ $output != *"invalid option"* ]]
  [[ $output != *"unbound variable"* ]]
  [[ $output == *kept.conf* ]]
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

@test "orphans: the two halves are separate -- wide scan, narrow claim" {
  # The other half of the fix, and it needs BOTH kinds of module in one tree to
  # say anything the previous test does not. Two modules put a file in the same
  # directory; only one is enabled. The enabled module's file must be claimed
  # and the disabled module's file must be an orphan -- from a single scan of a
  # single directory, which is the only arrangement that can tell the two rules
  # apart. Asserting merely that the output is non-empty, as this test once
  # did, is implied by the test above and cannot fail on its own.
  claim_one

  local other="$REPO/modules/other"
  mkdir -p "$other/home/.config/demo"
  printf 'description = "other"\n' >"$other/module.toml"
  printf 'content\n' >"$other/home/.config/demo/live.conf"
  fs_link_tree "$other"

  # `other` is on; `demo` is off but still contributes its directory.
  modules_enabled_dirs() { printf '%s\n' "$other"; }

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *kept.conf* ]]
  [[ $output != *live.conf* ]]
}

@test "orphans: deleting a file from the repo orphans its link" {
  # A sibling still lives in that directory, so the directory is still declared
  # and the scan still looks there.
  claim_one
  printf 'x\n' >"$MODULE/home/.config/demo/going.conf"
  fs_link_tree "$MODULE"
  rm "$MODULE/home/.config/demo/going.conf"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *going.conf* ]]
}

@test "orphans: the scan cannot see a directory no module declares any more" {
  # THE BOUNDARY OF THE DERIVED APPROACH, pinned deliberately rather than
  # discovered later. Where to look is derived from the files modules currently
  # ship, so emptying a directory in the repo also removes it from the scan and
  # the links left in $HOME become invisible -- to `dot doctor` AND to the
  # uninstall sweep, which shares this walk.
  #
  # The alternative is walking the whole of $HOME, which was rejected on cost.
  # This test exists so that if the trade is ever revisited it is revisited on
  # purpose: change the behaviour and this test should fail loudly.
  claim_one
  mkdir -p "$MODULE/home/.config/solo"
  printf 'x\n' >"$MODULE/home/.config/solo/only.conf"
  fs_link_tree "$MODULE"
  [ -L "$HOME/.config/solo/only.conf" ]

  # The whole directory leaves the repo; the link in $HOME stays behind.
  rm -r "${MODULE:?}/home/.config/solo"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *only.conf* ]]
  # Still sitting there, dangling, unreported.
  [ -L "$HOME/.config/solo/only.conf" ]
}
