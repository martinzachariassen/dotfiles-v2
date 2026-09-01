#!/usr/bin/env bats
#
# lib/dot.sh: root resolution and exit status.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "a clean script that sources the library exits 0" {
  # Regression: the EXIT trap was written as
  #   [[ $DOT_FAILURES -gt 0 ]] && exit 1; exit $?
  # When the test is false the && list returns 1, so $? is 1 and every
  # successful hook exited 1 -- which killed `dot apply` right after
  # core/apply.sh under `set -e`.
  cat >"$DOT_TMP/clean.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
ok "did the thing"
EOF
  run bash "$DOT_TMP/clean.sh"
  [ "$status" -eq 0 ]
}

@test "a script that calls fail exits 1" {
  cat >"$DOT_TMP/bad.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
fail "something is wrong"
EOF
  run bash "$DOT_TMP/bad.sh"
  [ "$status" -eq 1 ]
}

@test "fail does not stop execution" {
  # A doctor run must report every problem in one pass, not just the first.
  cat >"$DOT_TMP/two.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
fail "first"
fail "second"
echo "reached the end"
EOF
  run bash "$DOT_TMP/two.sh"
  [ "$status" -eq 1 ]
  [[ $output == *"reached the end"* ]]
}

@test "an explicit non-zero exit is preserved" {
  cat >"$DOT_TMP/code.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
exit 3
EOF
  run bash "$DOT_TMP/code.sh"
  [ "$status" -eq 3 ]
}

@test "the installed shim invokes the CLI from a clean environment" {
  # This is how `dot` is actually run. Regression: when ~/.local/bin/dot was a
  # symlink, bash set BASH_SOURCE to the symlink path, so bin/dot looked for
  # lib/ next to ~/.local/bin and failed. core/apply.sh now writes a shim.
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null

  [ -x "$HOME/.local/bin/dot" ]
  run env -u DOT_ROOT "$HOME/.local/bin/dot" --help
  [ "$status" -eq 0 ]
  [[ $output == *"usage: dot"* ]]
}

@test "the shim records the checkout it was installed from" {
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null
  run grep -c "$DOT_ROOT" "$HOME/.local/bin/dot"
  [ "$output" -ge 1 ]
}

@test "an inherited DOT_ROOT is not overridden" {
  run bash -c "DOT_ROOT='$DOT_ROOT' bash -c 'source \"$DOT_ROOT/lib/dot.sh\"; echo \$DOT_ROOT'"
  [ "$output" = "$DOT_ROOT" ]
}
