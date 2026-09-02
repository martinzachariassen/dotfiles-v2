#!/usr/bin/env bats
#
# install.sh -- the three guards, and nothing past them.
#
# This script installs Xcode CLT, Homebrew and bash 5 on the machine running it,
# so the only part a test may reach is the part that refuses to start. The
# safety mechanism is the PATH: the stub directory is the WHOLE of it, and every
# external command install.sh could touch after the guards exists there as a
# tripwire that records the call and fails. So a guard that stops firing does
# not run the real installer -- it trips the wire, the script dies on the next
# command, and the test says which guard let it through.
#
# `$BASH` by absolute path rather than the shebang, because with PATH set to the
# stub directory there is no `bash` in it to find.

load helper

setup() {
  setup_sandbox

  BIN="$DOT_TMP/stub"
  TRIPPED="$DOT_TMP/tripped"
  mkdir -p "$BIN"

  # #!/bin/sh, not env bash: PATH is about to be the stub directory alone, so
  # `#!/usr/bin/env bash` would have no bash to find and every stub would fail
  # to start. That failure is silent in the direction that matters -- a `uname`
  # that cannot run produces an empty string, which does not equal "Darwin", so
  # the macOS guard fires and its test passes without either stub working.
  local cmd
  for cmd in xcode-select brew git curl sudo sleep; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"%s"\nexit 1\n' \
      "$cmd" "$TRIPPED" >"$BIN/$cmd"
    chmod +x "$BIN/$cmd"
  done

  # The three the guards themselves call. Each defaults to a machine that WOULD
  # pass, so a test only has to override the one thing it is about -- and a
  # guard that reads the wrong value fails the test rather than passing it.
  printf '#!/bin/sh\ncase ${1:-} in -s) echo "${STUB_OS:-Darwin}";; -m) echo "${STUB_ARCH:-arm64}";; esac\n' \
    >"$BIN/uname"
  printf '#!/bin/sh\necho "${STUB_UID:-501}"\n' >"$BIN/id"
  chmod +x "$BIN/uname" "$BIN/id"
}

teardown() { teardown_sandbox; }

# Run install.sh with the stubs, in the sandbox, with the clone target pointed
# somewhere disposable in case anything ever gets that far.
bootstrap() {
  run env -i PATH="$BIN" HOME="$HOME" \
    DOTFILES_DIR="$DOT_TMP/checkout" \
    "$@" "$BASH" "$DOT_ROOT/install.sh"
}

# Called by every test: the guard has to have stopped the run, not merely
# complained on the way past.
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
  # The one guard whose absence is silent rather than loud: as root the install
  # succeeds, and leaves a Homebrew prefix and a repo the user cannot write to.
  bootstrap STUB_UID=0
  [[ $output == *"as root"* ]]
  assert_went_no_further
}

@test "guard: refuses an Intel Mac, and says what it found" {
  # Named, because "Apple Silicon only" on a Mac you believe is Apple Silicon is
  # the point at which you start doubting the script instead of the machine --
  # and under Rosetta that doubt would be misplaced.
  bootstrap STUB_ARCH=x86_64
  [[ $output == *"Apple Silicon only"* ]]
  [[ $output == *"x86_64"* ]]
  assert_went_no_further
}

@test "guard: the guards pass on the machine this repo targets" {
  # Otherwise the three tests above prove only that the script exits, which it
  # would also do if the first guard rejected everything. The tripwire is the
  # assertion here: reaching xcode-select means all three guards let a Darwin
  # arm64 non-root machine through.
  bootstrap
  [ -f "$TRIPPED" ]
  [[ $(cat "$TRIPPED") == xcode-select* ]]
  [[ $output != *"only"* ]]
}
