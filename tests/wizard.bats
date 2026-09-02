#!/usr/bin/env bats
#
# The wizard was the only shipped file with no tests, and it held three bugs
# that a single run would have caught. fzf is replaced by a shell function --
# function lookup beats PATH, so no stub binary is needed -- which makes the
# picker testable without a terminal.
#
# Several tests run the library in a fresh `bash -euo pipefail` process on
# purpose: two of these bugs only bite under `set -e`, and bats does not
# enable errexit inside a test body.

setup() {
  load helper
  setup_sandbox
}

teardown() { teardown_sandbox; }

# Run a snippet with the library loaded, under the same shell options bin/dot
# uses. This is what makes a `set -e` abort observable as a failed status.
in_strict_shell() {
  run bash -euo pipefail -c "source \"\$DOT_ROOT/lib/dot.sh\"; $1"
}

# --- The module picker ------------------------------------------------------

@test "picker: returns real module names, not words from the description" {
  # Regression. Rows outside the profile are marked with a space, and the old
  # `awk '{print $2}'` skipped leading whitespace -- so `dev-cli` came back as
  # "Extra" and `macos-defaults` as "macOS", and both were silently dropped by
  # modules_enabled as unknown. Only `zsh` survived, and only because its
  # description happens to start with the word "zsh".
  fzf() { cat; } # the user confirms every row offered

  # A preset that excludes most modules, so most markers are a space.
  run wizard_pick_modules "$(printf 'git\n')"

  [ "$status" -eq 0 ]
  [ "$output" = "$(modules_all)" ]
}

@test "picker: every returned name is a module that actually exists" {
  fzf() { cat; }
  local name
  while IFS= read -r name; do
    module_exists "$name" || {
      echo "picker returned '$name', which is not a module"
      return 1
    }
  done < <(wizard_pick_modules "$(printf 'git\n')")
}

@test "picker: a module in the preset is marked, and still returns its name" {
  fzf() { grep -F '*' | head -1; } # user takes the first marked row
  run wizard_pick_modules "$(printf 'git\n')"
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "picker: cancelling fzf yields nothing instead of killing the run" {
  # Regression. Esc makes fzf exit 130; inside `modules=$(...)` under `set -e`
  # that aborted the whole of `dot apply`, which also made the empty-result
  # fallback below it unreachable.
  in_strict_shell '
    fzf() { cat >/dev/null; return 130; }
    out=$(wizard_pick_modules "git")
    [[ -z $out ]] && echo EMPTY
    echo SURVIVED
  '
  [ "$status" -eq 0 ]
  [[ $output == *EMPTY* ]]
  [[ $output == *SURVIVED* ]]
}

# --- The `&&`-in-a-loop landmine --------------------------------------------
#
# The wizard's default-preset helper was `module_default "$name" && printf ...`,
# so a false test on the LAST iteration left the loop at status 1 and `set -e`
# killed the assignment. That helper is gone with the `custom` profile, but the
# identical shape lives on in modules_enabled -- and there pipefail carries the
# loop's status out through the trailing `| sort`, so it reaches the caller too.

@test "enabled: an unknown module sorting last does not abort the caller" {
  config_generate "A" "a@b.c" "$(printf 'git\nzzz-bogus\n')"
  in_strict_shell '
    list=$(modules_enabled)
    echo "list=[$(echo $list)]"
    echo SURVIVED
  '
  [ "$status" -eq 0 ]
  [[ $output == *"list=[git]"* ]]
  [[ $output == *SURVIVED* ]]
}

@test "enabled: a config where nothing is known is not an error" {
  config_generate "A" "a@b.c" "$(printf 'nope\n')"
  in_strict_shell '
    list=$(modules_enabled)
    [[ -z $list ]] && echo EMPTY
    echo SURVIVED
  '
  [ "$status" -eq 0 ]
  [[ $output == *EMPTY* ]]
  [[ $output == *SURVIVED* ]]
}

@test "enabled: an empty module list is not an error" {
  # The state the `none` profile writes.
  config_generate "A" "a@b.c" ""
  in_strict_shell '
    list=$(modules_enabled)
    [[ -z $list ]] && echo EMPTY
    echo SURVIVED
  '
  [ "$status" -eq 0 ]
  [[ $output == *EMPTY* ]]
  [[ $output == *SURVIVED* ]]
}

# --- Validation on apply -----------------------------------------------------

@test "validate: a config naming only real modules passes" {
  config_generate "A" "a@b.c" "$(printf 'git\nzsh\n')"
  run modules_require_known
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: an empty module list passes" {
  config_generate "A" "a@b.c" ""
  run modules_require_known
  [ "$status" -eq 0 ]
}

@test "validate: an unknown module stops the run and says what is valid" {
  # Hand-editing the config is the supported way to use the `none` profile, so
  # a typo must not be a warning that scrolls past while apply reports success.
  config_generate "A" "a@b.c" "$(printf 'git\ntypoo\n')"
  run modules_require_known
  [ "$status" -eq 1 ]
  [[ $output == *typoo* ]]
  [[ $output == *"do not exist"* ]]
  [[ $output == *available* ]]
  [[ $output == *git* ]]
}

@test "validate: every unknown name is listed, not just the first" {
  config_generate "A" "a@b.c" "$(printf 'aaa\ngit\nzzz\n')"
  run modules_require_known
  [ "$status" -eq 1 ]
  [[ $output == *aaa* ]]
  [[ $output == *zzz* ]]
}

# --- No `custom` profile ------------------------------------------------------

@test "wizard: offers none, and never offers custom" {
  # `custom` was a second way to hand-assemble a module list; the config file
  # is the first, and two ways to do it is one too many.
  local hits
  hits=$(grep -vE '^[[:space:]]*#' "$DOT_ROOT/lib/wizard.sh" | grep -c custom || true)
  [ "$hits" -eq 0 ]

  # The menu is whatever the picker feeds fzf on stdin, so echo it back out.
  fzf() {
    cat >&2
    printf 'none\n'
  }
  run wizard_run </dev/null
  [[ $output == *none* ]]
  [[ $output == *personal* ]]
  [[ $output != *custom* ]]
}

@test "wizard: the none profile writes an empty list and skips the picker" {
  fzf() { printf 'none\n'; }
  # Three answers: name (keep the default), email (keep the default), confirm.
  # This used to be `</dev/null`, which reached the confirm prompt at
  # end-of-input -- and since that read fell through to ${reply:-y}, the test
  # passed while proving nothing about a config anybody had agreed to.
  run wizard_run < <(printf '\n\ny\n')
  [ "$status" -eq 0 ]
  [[ $output == *"(none"* ]]
  [ -f "$DOT_CONFIG" ]
  [ "$(cfg_list 'modules.enabled')" = "" ]
}

@test "wizard: end-of-input at the confirm prompt cancels and writes nothing" {
  # Two bugs on one line. The read was bare, so Ctrl-D tripped errexit and the
  # wizard reported a crash -- "lib/wizard.sh:77: read ... (exit 1)" -- instead
  # of cancelling. And had it not, the fall-through was the worse half:
  # ${reply:-y} reads end-of-input as YES, so a closed terminal would have
  # written a config nobody confirmed, once, permanently.
  in_strict_shell '
    fzf() { printf "none\n"; }
    wizard_run </dev/null
    echo REACHED-THE-END
  '
  [ "$status" -eq 0 ]
  [[ $output == *"Cancelled"* ]]
  # __wizard_cancel exits, so nothing after wizard_run may run.
  [[ $output != *"REACHED-THE-END"* ]]
  [ ! -f "$DOT_CONFIG" ]
}

# --- The whole round trip ---------------------------------------------------

@test "round trip: what the picker returns is what apply enables" {
  # The end-to-end property the awk bug broke: names chosen in the wizard must
  # survive config_generate and come back out of modules_enabled unchanged.
  fzf() { cat; }
  local picked
  picked=$(wizard_pick_modules "$(printf 'git\n')")

  config_generate "Ada Lovelace" "ada@example.com" "$picked"

  # modules_enabled sorts; the picker does not. Compare as sets.
  [ "$(modules_enabled | sort)" = "$(printf '%s\n' "$picked" | sort)" ]
}

@test "round trip: every name the wizard writes is one apply will accept" {
  # The assertion here used to be `output != *"unknown module"*`, which cannot
  # fail: that string lives in bin/dot, which this test never runs, and
  # modules_enabled is silent by construction. Ask the validator instead --
  # modules_require_known is the function `dot apply` actually gates on.
  fzf() { cat; }
  config_generate "A" "a@b.c" "$(wizard_pick_modules "$(printf 'git\n')")"

  run modules_require_known
  [ "$status" -eq 0 ]
  # And nothing was rejected on the way through.
  [ -z "$(modules_unknown)" ]
}

# --- Stale module names -----------------------------------------------------

@test "enabled: reading the module list is silent, however often it is read" {
  # A single apply reads the list more than once -- the apply loop, the orphan
  # scan -- and every one of them is a `< <(modules_enabled)` PROCESS
  # SUBSTITUTION, i.e. a subshell. That is why warning from inside
  # modules_enabled cannot be deduplicated with a cache variable: the flag is
  # set in the subshell and thrown away with it. An earlier attempt passed a
  # test that called `modules_enabled >/dev/null` directly and still printed
  # the warning twice in a real run, so this test uses the real call shape.
  config_generate "A" "a@b.c" "$(printf 'git\nbogus\n')"
  run bash -c '
    source "$DOT_ROOT/lib/dot.sh"
    while IFS= read -r n; do :; done < <(modules_enabled)
    while IFS= read -r n; do :; done < <(modules_enabled)
    while IFS= read -r n; do :; done < <(modules_enabled_dirs)
  '
  [ "$status" -eq 0 ]
  # TOTALLY silent, not "silent about one phrase". The old assertion looked for
  # "unknown module", a string that lives in bin/dot and can never appear here,
  # so any wording of a warning added to modules_enabled would have slipped past
  # -- which is the entire failure this test is meant to prevent.
  [ -z "$output" ]
}

@test "unknown: each stale name is listed exactly once" {
  config_generate "A" "a@b.c" "$(printf 'git\nbogus\n')"
  run modules_unknown
  [ "$status" -eq 0 ]
  [ "$output" = "bogus" ]
}

@test "enabled: an unknown module is skipped, not applied" {
  config_generate "A" "a@b.c" "$(printf 'git\nbogus\n')"
  run modules_enabled
  [[ $output != *bogus* ]]
  [[ $output == *git* ]]
}
