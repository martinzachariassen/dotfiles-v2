#!/usr/bin/env bats
#
# install.sh: the three guards, and nothing past them. PATH is the stub
# directory alone; every later command is a tripwire that records and fails.

load helper

setup() {
  setup_sandbox

  BIN="$DOT_TMP/stub"
  TRIPPED="$DOT_TMP/tripped"
  mkdir -p "$BIN"

  # #!/bin/sh, not env bash: there is no bash on the stub-only PATH, and a
  # stub that cannot start makes `uname` print nothing, which fails the macOS
  # guard and passes its test without either stub working.
  local cmd
  for cmd in xcode-select brew git curl sudo sleep; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"%s"\nexit 1\n' \
      "$cmd" "$TRIPPED" >"$BIN/$cmd"
    chmod +x "$BIN/$cmd"
  done

  # Each defaults to a machine that WOULD pass, so a test overrides one thing.
  printf '#!/bin/sh\ncase ${1:-} in -s) echo "${STUB_OS:-Darwin}";; -m) echo "${STUB_ARCH:-arm64}";; esac\n' \
    >"$BIN/uname"
  printf '#!/bin/sh\necho "${STUB_UID:-501}"\n' >"$BIN/id"
  chmod +x "$BIN/uname" "$BIN/id"
}

teardown() { teardown_sandbox; }

# `$BASH` by absolute path: there is no `bash` on the stub PATH.
bootstrap() {
  run env -i PATH="$BIN" HOME="$HOME" \
    DOTFILES_DIR="$DOT_TMP/checkout" \
    "$@" "$BASH" "$DOT_ROOT/install.sh"
}

assert_went_no_further() {
  [ "$status" -ne 0 ]
  [ ! -f "$TRIPPED" ] || {
    echo "the guard did not stop the run; install.sh went on to call:"
    cat "$TRIPPED"
    return 1
  }
}

@test "guard: refuses a machine that is not macOS" {
  bootstrap STUB_OS=Linux
  [[ $output == *"macOS only"* ]]
  assert_went_no_further
}

@test "guard: refuses to run as root" {
  bootstrap STUB_UID=0
  [[ $output == *"as root"* ]]
  assert_went_no_further
}

@test "guard: refuses an Intel Mac, and says what it found" {
  bootstrap STUB_ARCH=x86_64
  [[ $output == *"Apple Silicon only"* ]]
  [[ $output == *"x86_64"* ]]
  assert_went_no_further
}

@test "guard: the guards pass on the machine this repo targets" {
  # Otherwise the tests above prove only that the script exits. Reaching
  # xcode-select means all three guards let the machine through.
  bootstrap
  [ -f "$TRIPPED" ]
  [[ $(cat "$TRIPPED") == xcode-select* ]]
  [[ $output != *"only"* ]]
}
