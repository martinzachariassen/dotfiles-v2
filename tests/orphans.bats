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
