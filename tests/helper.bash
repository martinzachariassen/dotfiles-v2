# shellcheck shell=bash
#
# Shared bats setup. Every test runs against a throwaway $HOME.

setup_sandbox() {
  DOT_TMP=$(mktemp -d)
  export DOT_TMP

  export HOME="$DOT_TMP/home"
  export DOT_STATE="$DOT_TMP/state"
  export DOT_CONFIG="$DOT_TMP/config.toml"
  export DOT_DRY_RUN=0
  mkdir -p "$HOME"

  # Pinned, not inherited: a developer machine exporting these would make a
  # real apply `mkdir -p` outside the sandbox.
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"

  # A mise shim resolves runtimes under $HOME; against the empty sandbox a bare
  # `python3` tries to install one over the network.
  local kept=() dir
  while IFS= read -r dir; do
    if [[ $dir != */mise/shims ]]; then kept+=("$dir"); fi
  done < <(tr ':' '\n' <<<"$PATH")
  PATH=$(
    IFS=:
    printf '%s' "${kept[*]}"
  )
  export PATH

  # The library is loaded from the real repo; only $HOME is fake.
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DOT_ROOT
  # shellcheck source=../lib/dot.sh
  source "$DOT_ROOT/lib/dot.sh"

  DOT_N_LINKED=0 DOT_N_RELINKED=0 DOT_N_BACKED_UP=0 DOT_N_UNCHANGED=0
  DOT_FAILURES=0 DOT_WARNINGS=0

  # fs_backup_used answers from the filesystem, so ids must not be shared.
  export DOT_RUN_ID="test-$BATS_TEST_NUMBER"
}

teardown_sandbox() {
  [[ -n ${DOT_TMP:-} && -d $DOT_TMP ]] && rm -rf "$DOT_TMP"
  return 0
}

# home_snapshot -- sorted listing of $HOME; diff before/after to prove nothing
# was written. ~/Library is pruned: brew and macOS write there on their own.
home_snapshot() {
  find "$HOME" -path "$HOME/Library" -prune -o -print | sort
}

# fixture_module NAME -- a module directory outside the repo.
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
