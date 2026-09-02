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
#
# Produced by running the real generator, not by printf'ing a lookalike. A
# hand-written copy is a second definition of the shim format: change
# core/apply.sh and the fixture keeps passing core/doctor.sh while every real
# machine fails it, so the six doctor tests below would go on proving something
# about a file the repo no longer writes.
pass_core_checks() {
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null
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

@test "doctor: a stale module name is a failure, not a shrug" {
  # doctor's job is to predict what will stop the next apply, and
  # modules_require_known will. Reported rather than fatal because doctor is the
  # read-only verb and has to reach the checks below this one -- so the risk is
  # the opposite of apply's: a message that scrolls past under a green Result
  # line. Both halves are asserted.
  config_generate "A" "a@b.c" "$(printf 'git\ntypoo\n')"
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"unknown module 'typoo'"* ]]
  [[ $output != *"Everything looks right"* ]]
  # It kept going: the per-module section for the name that IS real still ran.
  [[ $output == *"Module: git"* ]]
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

@test "config: with no config yet, points at --init instead of opening an editor" {
  # The bare `dot config` path had no test at all, and its failure mode is
  # $EDITOR opening an empty buffer at a path nothing reads -- you type a config,
  # save it, and the tool ignores it because the wizard never ran.
  EDITOR=false dot config
  [ "$status" -ne 0 ]
  [[ $output == *"dot config --init"* ]]
}

@test "config: opens \$EDITOR on the config file, and on nothing else" {
  # Pins the two things that can be wrong here: which program is run, and which
  # path it is handed. `${EDITOR:-vi}` unquoted would also split an EDITOR with
  # arguments -- a real configuration -- so the fixture has one.
  config_generate "A" "a@b.c" ""
  printf '#!/usr/bin/env bash\nprintf "EDITED[%%s]\\n" "$@"\n' >"$DOT_TMP/fake-editor"
  chmod +x "$DOT_TMP/fake-editor"

  EDITOR="$DOT_TMP/fake-editor" dot config
  [ "$status" -eq 0 ]
  [ "$output" = "EDITED[$DOT_CONFIG]" ]
}

@test "apply: a dry run on a fresh machine does not run the wizard" {
  # config_generate declines to write under DOT_DRY_RUN, so the wizard asked
  # for a profile, a module list, a name, an email and a confirmation, then
  # threw all five answers away -- a preview of a run that could not happen.
  # The fzf stub is the tripwire: if the wizard is reached, it says so.
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\necho WIZARD-RAN\n' >"$DOT_TMP/stub/fzf"
  chmod +x "$DOT_TMP/stub/fzf"

  run env PATH="$DOT_TMP/stub:$PATH" "$DOT_ROOT/bin/dot" apply --dry-run

  [ "$status" -ne 0 ]
  [[ $output != *"WIZARD-RAN"* ]]
  [[ $output == *"dot config --init"* ]]
  # And not the misleading one: phase 1 was skipped on purpose, so there is no
  # brew output above to check.
  [[ $output != *"brew output above"* ]]
  [ ! -f "$DOT_CONFIG" ]
}

@test "doctor: with no config, says how to make one rather than crashing" {
  # Without the guard, doctor runs cfg_list against a file that is not there and
  # the first thing the user sees is a dasel error.
  run "$DOT_ROOT/bin/dot" doctor
  [ "$status" -ne 0 ]
  [[ $output == *"dot config --init"* ]]
  [[ $output != *dasel* ]]
}
