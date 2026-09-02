#!/usr/bin/env bats
#
# The removal half of lib/fs.sh, and one end-to-end pass over uninstall.sh.
#
# What these are really pinning is the set of things an uninstall must NOT
# touch. Getting "did it delete the link" right is easy; the expensive bugs are
# all in the other direction -- a real file at a path a module used to own, a
# link someone else made, a backup tree holding the only copy of a config.

setup() {
  load helper
  setup_sandbox

  # A repo root inside the sandbox, so "points into the repo" is controllable
  # and no test depends on the real checkout. Same shape as orphans.bats.
  REPO="$DOT_TMP/repo"
  MODULE="$REPO/modules/demo"
  mkdir -p "$MODULE/home/.config/demo"
  printf 'description = "demo"\nsudo = false\n' >"$MODULE/module.toml"
  printf 'content\n' >"$MODULE/home/.config/demo/kept.conf"
  DOT_ROOT="$REPO"
}

teardown() { teardown_sandbox; }

link_one() {
  modules_enabled_dirs() { printf '%s\n' "$MODULE"; }
  fs_link_tree "$MODULE"
}

# --- fs_unlink ----------------------------------------------------------------

@test "unlink: removes a symlink" {
  link_one
  fs_unlink "$HOME/.config/demo/kept.conf"
  [ ! -e "$HOME/.config/demo/kept.conf" ]
  [ "$DOT_N_REMOVED" -eq 1 ]
}

@test "unlink: leaves a real file alone" {
  # The whole reason fs_unlink tests for -L instead of calling rm. A real file
  # at a path a module once owned is the user's, whoever put it there.
  mkdir -p "$HOME/.config/demo"
  printf 'mine\n' >"$HOME/.config/demo/kept.conf"
  fs_unlink "$HOME/.config/demo/kept.conf"
  [ -f "$HOME/.config/demo/kept.conf" ]
  [ "$DOT_N_REMOVED" -eq 0 ]
}

@test "unlink: a dry run announces and changes nothing" {
  link_one
  DOT_DRY_RUN=1
  run fs_unlink "$HOME/.config/demo/kept.conf"
  [[ $output == *unlink* ]]
  [ -L "$HOME/.config/demo/kept.conf" ]
}

# --- fs_discard ---------------------------------------------------------------

@test "discard: removes a generated file" {
  printf 'generated\n' >"$HOME/generated.conf"
  fs_discard "$HOME/generated.conf"
  [ ! -e "$HOME/generated.conf" ]
}

@test "discard: a missing file is success, not failure" {
  # Every caller runs on a machine that may have been half-uninstalled already.
  run fs_discard "$HOME/never-existed"
  [ "$status" -eq 0 ]
}

@test "discard: a dry run changes nothing" {
  printf 'generated\n' >"$HOME/generated.conf"
  DOT_DRY_RUN=1
  fs_discard "$HOME/generated.conf"
  [ -f "$HOME/generated.conf" ]
}

# --- fs_repo_links --------------------------------------------------------------

@test "repo links: finds a link into the repo" {
  link_one
  run fs_repo_links
  [[ $output == *kept.conf* ]]
}

@test "repo links: finds links from a DISABLED module too" {
  # An uninstall has nothing enabled by definition, so this is not an edge case
  # -- it is the only case. fs_orphans and fs_repo_links share this walk
  # precisely so that neither verb can develop its own idea of which links
  # belong to the repo.
  link_one
  modules_enabled_dirs() { :; }
  run fs_repo_links
  [[ $output == *kept.conf* ]]
}

@test "repo links: ignores a link pointing outside the repo" {
  link_one
  printf 'x\n' >"$DOT_TMP/elsewhere.txt"
  ln -s "$DOT_TMP/elsewhere.txt" "$HOME/.config/demo/foreign.conf"

  run fs_repo_links
  [[ $output != *foreign.conf* ]]
}

@test "repo links: ignores real files" {
  link_one
  printf 'x\n' >"$HOME/.config/demo/notes.txt"
  run fs_repo_links
  [[ $output != *notes.txt* ]]
}

# --- uninstall.sh -----------------------------------------------------------------

@test "uninstall: --dry-run exits clean and changes nothing" {
  # Against the REAL repo, because the point is that the script as shipped runs
  # end to end -- module hooks included -- without touching anything. $HOME is
  # still the sandbox, so there is nothing of the caller's to lose.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  fs_link_tree "$DOT_ROOT/modules/git"
  [ -L "$HOME/.config/git/config" ]

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Nothing was changed"* ]]
  [ -L "$HOME/.config/git/config" ]
  [ -d "$DOT_ROOT/.git" ]
}

@test "uninstall: refuses an unknown option" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option"* ]]
}

@test "uninstall: refuses to run unattended without --dry-run" {
  # No terminal in bats, so this exercises the guard rather than simulating it.
  # Without it, a copy-pasted line in a CI script would take out the machine.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" </dev/null
  [ "$status" -ne 0 ]
  [[ $output == *"Refusing to run unattended"* ]]
}

@test "uninstall: the backup tree survives a dry run and is reported" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$DOT_STATE/backups/20240101-000000"
  printf 'precious\n' >"$DOT_STATE/backups/20240101-000000/.zshrc"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"kept"* ]]
  [ -f "$DOT_STATE/backups/20240101-000000/.zshrc" ]
}
