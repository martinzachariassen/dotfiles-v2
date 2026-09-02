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
  printf 'description = "demo"\n' >"$MODULE/module.toml"
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

  # The whole of $HOME, not just the link. containers/remove.sh asked `colima
  # status` whether the VM was running, and that question CREATES ~/.colima --
  # so the dry run wrote to the disk it had just promised not to touch, and
  # every named assertion in this test still passed.
  local before after
  before=$(home_snapshot)

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Nothing was changed"* ]]
  [ -L "$HOME/.config/git/config" ]
  [ -d "$DOT_ROOT/.git" ]

  after=$(home_snapshot)
  [ "$before" = "$after" ] || {
    echo "the dry run wrote to \$HOME:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    return 1
  }
}

@test "uninstall: applications are dealt with before Homebrew is" {
  # The one ordering the script cannot get wrong. Homebrew MOVES a cask's .app
  # to /Applications, so its own uninstaller leaves it there; only `brew` knows
  # which apps those are, and only until it is gone. Removing casks after the
  # handoff would strand every GUI app on the machine.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]

  apps=$(printf '%s\n' "$output" | grep -n '^Applications$' | cut -d: -f1)
  brew=$(printf '%s\n' "$output" | grep -n '^Homebrew and the repo$' | cut -d: -f1)
  [ -n "$apps" ]
  [ -n "$brew" ]
  [ "$apps" -lt "$brew" ]
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

@test "uninstall: a state directory holding foreign files is left alone" {
  # The live case that produced this branch: ~/.local/state/dotfiles on the
  # author's machine holds a brew-bundle.log from v1, which nothing in this
  # repo writes or references. The old code was `rm -rf "${DOT_STATE:?}"`, so
  # an uninstall deleted a file it did not create and could not restore -- and
  # never mentioned it, in the preview or afterwards.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$DOT_STATE"
  printf 'from an older tool\n' >"$DOT_STATE/brew-bundle.log"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"left alone"* ]]
  [[ $output != *"remove  ~/.local/state"* ]]
  [ -f "$DOT_STATE/brew-bundle.log" ]
}

@test "uninstall: removing the state directory is announced in the preview" {
  # An empty backup tree is the one case where the directory really does go,
  # and a deletion a --dry-run does not mention is a deletion nobody agreed to.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$DOT_STATE/backups"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"remove"* ]]
  [[ $output != *"left alone"* ]]
  # ...and the preview did not act on it.
  [ -d "$DOT_STATE/backups" ]
}

@test "uninstall: no state directory at all says nothing beyond None to keep" {
  # find exits 1 on a directory that is not there, and this used to be a bare
  # `stray=$(find ...)` -- which under `set -e` aborted the whole uninstall
  # before it reached Homebrew. The -d guard is load-bearing.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  [ ! -d "$DOT_STATE" ]

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"None to keep"* ]]
  [[ $output != *"left alone"* ]]
  [[ $output != *"remove  ~/.local/state"* ]]
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
