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

# --- Failure reporting ------------------------------------------------------

# Run a snippet exactly as a module hook runs: a real script file in its own
# bash process, strict mode, library sourced. A file rather than `bash -c`
# because the report is built from BASH_SOURCE, and `-c` has none.
as_hook() {
  local script="$DOT_TMP/hook.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo "source \"$DOT_ROOT/lib/dot.sh\""
    echo "$1"
  } >"$script"
  run bash "$script"
}

@test "err: a crash names the file, the command and the status" {
  # Without this a failing hook is an exit code and nothing else, because the
  # driver runs it in a separate process.
  as_hook 'cp /nonexistent/theme.conf "$HOME/theme.conf"'
  [ "$status" -ne 0 ]
  [[ $output == *"hook.sh"* ]]
  [[ $output == *"cp /nonexistent/theme.conf"* ]]
  [[ $output == *"exit 1"* ]]
}

@test "err: the report survives failing inside a function" {
  # bash 3.2 cannot give the failing line here -- it reports the function's
  # definition line -- which is why no line number is printed at all.
  as_hook 'inner() { cp /nonexistent/x "$HOME/x"; }; inner'
  [ "$status" -ne 0 ]
  [[ $output == *"cp /nonexistent/x"* ]]
  [[ ! $output =~ hook\.sh:[0-9] ]]
}

@test "err: a failure handled inside \$() is not reported" {
  # errtrace makes command substitutions inherit the ERR trap, so toml_get's
  # own "missing key" probe -- `if raw=$(dasel ...)` -- used to report a
  # failure on every config default. A reporter that cries wolf gets ignored.
  as_hook "val=\$(toml_get '$DOT_ROOT/modules/git/module.toml' nosuchkey FALLBACK)
           echo \"val=\$val\""
  [ "$status" -eq 0 ]
  [[ $output == *"val=FALLBACK"* ]]
  [[ $output != *"exit 1"* ]]
}

@test "err: reported once, not once per stack frame" {
  # The trap fires again at each frame as the stack unwinds.
  as_hook 'a() { false; }; b() { a; }; c() { b; }; c'
  [ "$status" -ne 0 ]
  [ "$(grep -c 'exit 1' <<<"$output")" -eq 1 ]
}

# --- Portability ------------------------------------------------------------

@test "shipped code uses no bash 4 features" {
  # macOS ships bash 3.2.57 and this repo installs no other bash, so every
  # `#!/usr/bin/env bash` resolves to it. Associative arrays, mapfile and
  # ${x,,} all fail there. One shipped once because fs_orphans had no test.
  local hits
  hits=$(cat "$DOT_ROOT"/lib/*.sh "$DOT_ROOT"/core/*.sh "$DOT_ROOT"/bin/dot \
    "$DOT_ROOT"/modules/*/*.sh "$DOT_ROOT"/install.sh |
    grep -vE '^[[:space:]]*#' |
    grep -nE 'declare -A|local -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)' || true)
  [ -z "$hits" ] || {
    echo "bash 4 only constructs found:"
    echo "$hits"
    false
  }
}
