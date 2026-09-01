#!/usr/bin/env bats
#
# fs_orphans had no test at all. That is how a `local -A` -- an associative
# array, which is bash 4 only while macOS ships 3.2 -- reached the repo and
# failed at runtime with "local: -A: invalid option" while CI stayed green.
#
# These cover the behaviour, and by exercising the function under the real
# system bash they also pin the version constraint.

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

@test "orphans: runs on the system bash without bash 4 features" {
  # The direct regression. `local -A` here exited non-zero with a shell usage
  # error rather than doing anything.
  claim_one
  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *"invalid option"* ]]
  [[ $output != *"usage:"* ]]
}
