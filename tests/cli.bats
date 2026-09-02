#!/usr/bin/env bats
#
# bin/dot itself: how it reads the command line.
#
# This was the least-tested part of the repo, and it hid the worst kind of bug:
# `dot apply --dry` matched no option, so the mistyped flag was ignored and the
# machine was modified for real. Argument parsing now refuses anything it does
# not recognise, and these tests hold it to that.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

dot() { run "$DOT_ROOT/bin/dot" "$@"; }

# Make the CORE checks pass, so a doctor test can isolate the one thing it is
# about and the status cannot have come from somewhere else. What
# core/doctor.sh looks for is a shim on PATH naming this checkout.
pass_core_checks() {
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\nexport DOT_ROOT="%s"\nexec "$DOT_ROOT/bin/dot" "$@"\n' \
    "$DOT_ROOT" >"$HOME/.local/bin/dot"
  chmod +x "$HOME/.local/bin/dot"
  export PATH="$HOME/.local/bin:$PATH"
}

@test "cli: no arguments prints the usage" {
  dot
  [ "$status" -eq 0 ]
  [[ $output == *"usage: dot"* ]]
}

@test "cli: an unknown command exits 1 and shows the usage" {
  dot frobnicate
  [ "$status" -eq 1 ]
  [[ $output == *"unknown command frobnicate"* ]]
  [[ $output == *"usage: dot"* ]]
}

@test "apply: a mistyped --dry-run is refused, not ignored" {
  # The regression. `--dry` used to fall through to a real apply.
  dot apply --dry
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--dry'"* ]]
  # And it stopped before phase 1, so nothing was installed on the way out.
  [[ $output != *"Core packages"* ]]
}

@test "apply: --dry-run is accepted and changes nothing" {
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Dry run: nothing was changed."* ]]
  # The clearest evidence a dry run stayed dry: the shim it would have written.
  [ ! -e "$HOME/.local/bin/dot" ]
}

@test "doctor: an unlinked module fails the whole run" {
  # The regression, end to end and in the shape a user would hit it: enable a
  # module, do not apply it, ask whether the machine is healthy. doctor called
  # module_doctor as `|| true`, so it listed the unlinked files, then printed
  # "Everything looks right" and exited 0.
  config_generate "A" "a@b.c" "git"
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"not linked"* ]]
  [[ $output != *"Everything looks right"* ]]
}

@test "doctor: a warning is not drowned out by the summary" {
  # Same shape as the bug above, one severity down. An orphaned link is
  # reported and never deleted -- so the run has something to say and nothing
  # to fail on, and the Result line used to answer "Everything looks right."
  config_generate "A" "a@b.c" ""
  pass_core_checks

  mkdir -p "$HOME/.config/git"
  ln -s "$DOT_ROOT/bin/dot" "$HOME/.config/git/leftover"

  run "$DOT_ROOT/bin/dot" doctor

  [[ $output == *"unclaimed"* ]]
  [[ $output != *"Everything looks right"* ]]
  [[ $output == *"warnings above"* ]]
  # Still a success. A warning is not a failure, and `dot doctor && ...` has
  # to keep working for anyone who has not tidied up yet.
  [ "$status" -eq 0 ]
}

@test "doctor: a clean machine still says so" {
  # The other half, and the reason this is a test rather than an assumption: a
  # summary that never says "fine" is exactly as useless as one that always
  # does, and the new branch sits between the caller and that answer.
  config_generate "A" "a@b.c" ""
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 0 ]
  [[ $output == *"Everything looks right"* ]]
}

@test "doctor: a shim that lost its executable bit is not called missing" {
  # One test was answering two questions. `[[ -x $shim ]]` alone reported a
  # shim sitting right there as "not installed in ~/.local/bin", which sends
  # you to `dot apply` hunting for a file you already have -- while the real
  # symptom is a "Permission denied" naming the shim and explaining nothing.
  # A check that misdescribes what it found is worse than one that stays quiet.
  config_generate "A" "a@b.c" ""
  pass_core_checks
  chmod -x "$HOME/.local/bin/dot"

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"not executable"* ]]
  [[ $output != *"not installed"* ]]
}

@test "doctor: a shim that is genuinely absent is still called missing" {
  # The other side of the split: widening -x to -f would have been the easy
  # fix and the wrong one, because then a non-executable shim reports
  # "✓ dot installed" while the command dies. Both branches keep their word.
  config_generate "A" "a@b.c" ""

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"not installed in ~/.local/bin"* ]]
  [[ $output != *"not executable"* ]]
}

@test "config: an unknown option is refused" {
  dot config --initt
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--initt'"* ]]
}

@test "config: --init refuses to overwrite a config that already exists" {
  config_generate "A" "a@b.c" ""

  dot config --init
  [ "$status" -ne 0 ]
  [[ $output == *"already exists"* ]]
}
