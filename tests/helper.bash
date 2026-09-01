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

  # The library is loaded from the real repo; only $HOME is fake.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DOT_ROOT
  # shellcheck source=../lib/dot.sh
  source "$DOT_ROOT/lib/dot.sh"

  # Counters are globals; reset them so tests do not see each other's tallies.
  DOT_N_LINKED=0 DOT_N_RELINKED=0 DOT_N_BACKED_UP=0 DOT_N_UNCHANGED=0
  DOT_FAILURES=0
  __DOT_BACKUP_DIR=''
}

teardown_sandbox() {
  [[ -n ${DOT_TMP:-} && -d $DOT_TMP ]] && rm -rf "$DOT_TMP"
  return 0
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
