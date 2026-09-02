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

@test "the shim records the checkout in the exact form its readers grep for" {
  # Three files agree on one string and nothing used to hold them together.
  # core/apply.sh WRITES `export DOT_ROOT="<path>"`; core/doctor.sh and
  # uninstall.sh both `grep -qF 'DOT_ROOT="<path>"'` to decide whether the shim
  # belongs to this checkout. The old assertion here was `grep -c "$DOT_ROOT"`,
  # which passes for any shim mentioning the path in any form -- so dropping
  # the quotes would keep this green while doctor started reporting a foreign
  # checkout and the uninstaller stopped removing the file at all.
  #
  # Written as the readers' own expression so the test fails with them.
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null
  run grep -qF "DOT_ROOT=\"$DOT_ROOT\"" "$HOME/.local/bin/dot"
  [ "$status" -eq 0 ]
}

@test "doctor and uninstall recognise the shim core/apply.sh just wrote" {
  # The coupling itself, end to end: generator and both readers in one test.
  # Neither reader is stubbed, so a change to any of the three has to keep the
  # other two working.
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null

  run bash "$DOT_ROOT/core/doctor.sh"
  [[ $output == *"dot         installed"* ]]
  [[ $output != *"different checkout"* ]]
}

@test "a shim from another checkout is left alone, not claimed" {
  # The other side of the same string. Ownership has to be provable, because
  # the uninstaller deletes on the strength of it.
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\nexport DOT_ROOT="/somewhere/else"\n' \
    >"$HOME/.local/bin/dot"
  chmod +x "$HOME/.local/bin/dot"

  run bash "$DOT_ROOT/core/doctor.sh"
  [[ $output == *"different checkout"* ]]
}

@test "an inherited DOT_ROOT is not overridden" {
  run bash -c "DOT_ROOT='$DOT_ROOT' bash -c 'source \"$DOT_ROOT/lib/dot.sh\"; echo \$DOT_ROOT'"
  [ "$output" = "$DOT_ROOT" ]
}

# A checkout at PATH, reached through PATH -- the shape a bad clone location
# really has, rather than a DOT_ROOT pointing at nothing. Only lib/ is needed:
# the guard runs before the first source, and nothing else is read at load time.
checkout_at() {
  local dir="$DOT_TMP/$1"
  mkdir -p "$dir"
  ln -s "$DOT_ROOT/lib" "$dir/lib"
  printf '%s\n' "$dir"
}

@test "root: every character that survives quoting is refused" {
  # One test, because the list IS the rule. Each of these is baked verbatim into
  # a script the repo generates -- the shim, and the throwaway uninstall.sh
  # execs into -- by an unquoted heredoc. A `"` ends the string early, so the
  # throwaway becomes a syntax error and typing `remove` removes nothing at all;
  # a backtick or $( ) is not a broken string but a command the generated script
  # runs; a backslash escapes whatever follows into something else.
  local bad dir
  for bad in 'dot"files' 'dot`id`files' 'dot$(id)files' 'back\slash'; do
    dir=$(checkout_at "$bad")
    run env DOT_ROOT="$dir" bash -c 'source "$DOT_ROOT/lib/dot.sh"'
    [ "$status" -ne 0 ] || {
      echo "accepted a checkout path containing: $bad"
      return 1
    }
    [[ $output == *"cannot be quoted safely"* ]]
    # Named, not just described. "your path is bad" over a path you cannot see
    # is not something you can act on.
    [[ $output == *"$bad"* ]]
  done
}

@test "root: an ordinary path with spaces or non-ASCII is left alone" {
  # The failure mode that gets a guard like this deleted: refusing paths people
  # actually have. A space was never the problem -- every use of $DOT_ROOT is
  # already quoted, and quoting is exactly what the four characters above defeat.
  local dir
  dir=$(checkout_at 'my dotfiles æøå')

  run env DOT_ROOT="$dir" bash -c 'source "$DOT_ROOT/lib/dot.sh"; ok loaded'
  [ "$status" -eq 0 ]
  [[ $output == *loaded* ]]
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

@test "err: a failure inside a function names the failing line" {
  # The whole point of moving to bash 5. On 3.2 this reported the function's
  # DEFINITION line instead, which is why the number used to be left out
  # altogether -- a confidently wrong line sends you to the wrong place.
  #
  # as_hook writes shebang, `set`, `source`, then the snippet, so the failure
  # is on line 4. Pinned exactly: "some number" would have passed on 3.2 too.
  as_hook 'inner() { cp /nonexistent/x "$HOME/x"; }; inner'
  [ "$status" -ne 0 ]
  [[ $output == *"cp /nonexistent/x"* ]]
  [[ $output == *"hook.sh:4:"* ]]
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

# --- The bash version -------------------------------------------------------

@test "bash: the suite itself runs under bash 5" {
  # The repo targets bash 5: install.sh installs it, bin/dot re-execs into it,
  # lib/dot.sh refuses to load without it. If bats runs under macOS's own 3.2
  # instead, every other test here is exercising the wrong shell -- so say so
  # loudly rather than leaving it to a syntax error somewhere unrelated.
  [ "${BASH_VERSINFO[0]}" -ge 5 ]
}

@test "bash: the library refuses to load under an old bash" {
  # /bin/bash is macOS's 3.2. The guard is what turns "syntax error near
  # unexpected token" in a file you never opened into one actionable line.
  [ -x /bin/bash ] || skip 'no /bin/bash on this machine'
  /bin/bash -c '((BASH_VERSINFO[0] < 5))' || skip '/bin/bash is already bash 5'

  run /bin/bash -c "source '$DOT_ROOT/lib/dot.sh'"
  [ "$status" -ne 0 ]
  [[ $output == *"bash 5"* ]]
  [[ $output == *"brew install bash"* ]]
}
