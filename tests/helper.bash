# shellcheck shell=bash
#
# Shared bats setup.
#
# Every test runs against a throwaway $HOME. Nothing in tests/ may touch the
# real home directory -- these tests move and delete files for a living.

setup_sandbox() {
  DOT_TMP=$(mktemp -d)
  export DOT_TMP

  export HOME="$DOT_TMP/home"
  export DOT_STATE="$DOT_TMP/state"
  export DOT_CONFIG="$DOT_TMP/config.toml"
  export DOT_DRY_RUN=0
  mkdir -p "$HOME"

  # Pinned, not inherited. lib/dot.sh derives DOT_CONFIG_HOME and
  # DOT_STATE_HOME from these, and core/apply.sh runs `mkdir -p` on both -- so
  # on a developer machine that exports either of them, a test doing a real
  # apply created directories OUTSIDE the sandbox. Overriding $HOME alone is
  # not enough to contain a test suite; anything $HOME is only a default for
  # has to be pinned too.
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"

  # The library is loaded from the real repo; only $HOME is fake.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DOT_ROOT
  # shellcheck source=../lib/dot.sh
  source "$DOT_ROOT/lib/dot.sh"

  # Counters are globals; reset them so tests do not see each other's tallies.
  DOT_N_LINKED=0 DOT_N_RELINKED=0 DOT_N_BACKED_UP=0 DOT_N_UNCHANGED=0
  DOT_FAILURES=0 DOT_WARNINGS=0

  # A fresh id per test, so one test's backup directory is never mistaken for
  # the next one's. DOT_STATE moves with the sandbox too, which makes this belt
  # and braces -- but fs_backup_used answers from the filesystem now, and a
  # shared id is exactly the kind of thing that would make it answer wrongly.
  export DOT_RUN_ID="test-$BATS_TEST_NUMBER"
}

teardown_sandbox() {
  [[ -n ${DOT_TMP:-} && -d $DOT_TMP ]] && rm -rf "$DOT_TMP"
  return 0
}

# home_snapshot -- a sorted listing of everything under $HOME that this repo
# could plausibly be responsible for. Compare one taken before an operation
# with one taken after to assert that nothing was written.
#
# Naming the paths you expect to survive only tests the paths you thought of,
# which is how `colima status` got away with creating ~/.colima inside both a
# doctor run and an uninstall dry run.
#
# ~/Library is pruned because it is not ours: Homebrew caches into
# ~/Library/Caches the moment anything shells out to `brew`, and macOS writes
# preferences there. Nothing in this repo links or generates below it.
home_snapshot() {
  find "$HOME" -path "$HOME/Library" -prune -o -print | sort
}

# fixture_module NAME -- a module directory outside the repo, so tests can
# invent trees without polluting modules/.
fixture_module() {
  local dir="$DOT_TMP/modules/$1"
  mkdir -p "$dir/home"
  printf '%s\n' "$dir"
}

# fixture_file DIR REL CONTENT -- create a file inside a fixture's home/.
fixture_file() {
  local dir=$1 rel=$2 content=${3:-content}
  mkdir -p "$(dirname "$dir/home/$rel")"
  printf '%s\n' "$content" >"$dir/home/$rel"
}
