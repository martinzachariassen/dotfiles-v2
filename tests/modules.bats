#!/usr/bin/env bats
#
# The module hook driver.
#
# module_doctor had no tests at all, and that is exactly what shipped the worst
# bug in the repo: bin/dot called it as `module_doctor "$name" || true`, so
# neither a drifted file tree nor a failing doctor.sh ever reached
# DOT_FAILURES. `dot doctor` printed the individual warnings, then
# "Everything looks right", and exited 0 over a module that was not linked at
# all -- the one answer a health check must never get wrong.
#
# Every test here asserts on the TALLY, not on the return value, because the
# tally is what becomes the exit status.

setup() {
  load helper
  setup_sandbox

  # A repo root inside the sandbox, so modules can be invented without
  # touching the real modules/ directory. The library is already loaded from
  # the real checkout; only the registry moves.
  REPO="$DOT_TMP/repo"
  DOT_ROOT="$REPO"
}

teardown() { teardown_sandbox; }

# make_module NAME -- a module in the fake repo, with the manifest the registry
# requires in order to see it at all.
make_module() {
  local dir="$REPO/modules/$1"
  mkdir -p "$dir/home"
  printf 'description = "%s"\n' "$1" >"$dir/module.toml"
  printf '%s\n' "$dir"
}

# hook DIR NAME STATUS -- a hook that exits with STATUS and nothing else. Plain
# bash on purpose: it must not source the library, because the fake repo has no
# lib/ and a hook that needs one would be testing the wrong thing.
hook() {
  printf '#!/usr/bin/env bash\nexit %s\n' "$3" >"$1/$2"
}

# --- module_doctor ----------------------------------------------------------

@test "doctor: a module whose files are not linked is a failure" {
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"

  module_doctor demo
  [ "$DOT_FAILURES" -eq 1 ]
}

@test "doctor: a doctor.sh that exits non-zero is a failure" {
  local m
  m=$(make_module demo)
  hook "$m" doctor.sh 1

  module_doctor demo
  [ "$DOT_FAILURES" -eq 1 ]
}

@test "doctor: a healthy module adds nothing to the tally" {
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  fs_link_tree "$m"
  hook "$m" doctor.sh 0

  module_doctor demo
  [ "$DOT_FAILURES" -eq 0 ]
}

@test "doctor: a module with no hook and no files is not a failure" {
  make_module demo >/dev/null

  module_doctor demo
  [ "$DOT_FAILURES" -eq 0 ]
}

@test "doctor: a packages-only module says so instead of printing nothing" {
  # `dot doctor` printed "Module: apps" with nothing at all underneath it,
  # which reads as a check that died quietly -- the one thing a health report
  # must never do. Same reason uninstall.sh prints "None found." per section.
  make_module demo >/dev/null

  run module_doctor demo
  [ "$status" -eq 0 ]
  [[ $output == *"nothing to check"* ]]
}

@test "doctor: a module whose files are all linked says so" {
  # The other silent section, and the more common one: fs_check_tree prints
  # drift and nothing else, so a healthy module with no doctor.sh -- which is
  # modules/git on any working machine -- reported by saying nothing.
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  fs_link_tree "$m" >/dev/null

  run module_doctor demo
  [ "$status" -eq 0 ]
  [[ $output == *"all linked"* ]]
}

@test "doctor: drift and a failing hook are both reported, in one pass" {
  # Checking the file tree must not short-circuit the hook. A module can be
  # unlinked AND broken, and a doctor that stops at the first problem turns
  # one run into two.
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  hook "$m" doctor.sh 1

  module_doctor demo
  [ "$DOT_FAILURES" -eq 2 ]
}

@test "doctor: counting a failure does not abort the caller" {
  # bin/dot calls module_doctor bare, inside a `while read` loop under `set -e`.
  # If it returned the failure instead of counting it, the first bad module
  # would end the run and every module after it would go unchecked -- so the
  # status has to arrive at the very end, from the EXIT trap, and not before.
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"

  # `env -u DOT_ROOT` so the library loads from the real checkout: lib/dot.sh
  # only derives the root from its own location when nothing is inherited, and
  # the fake repo has no lib/ to load. The registry is pointed at the fake one
  # afterwards, which is the only part these tests want to move.
  run env -u DOT_ROOT bash -euo pipefail -c "
    source \"$BATS_TEST_DIRNAME/../lib/dot.sh\"
    DOT_ROOT='$REPO'
    module_doctor demo
    echo REACHED-THE-END
  "
  [ "$status" -eq 1 ]
  [[ $output == *"REACHED-THE-END"* ]]
}

# --- The warning channel -----------------------------------------------------
#
# A hook runs in its own process, so "I said something, but nothing is broken"
# reaches the driver only as a number. Both wrong readings of that number were
# in the tree at the same time: doctor threw it away with `|| true`, and apply
# called it a crash with `if ! module_run_hook`. These tests pin both ends --
# a hook really does leave with DOT_STATUS_WARN, and the driver really does
# tell it apart from a failure.

@test "doctor: a doctor.sh that only warns is a warning, not a failure" {
  local m
  m=$(make_module demo)
  hook "$m" doctor.sh 2

  module_doctor demo
  [ "$DOT_FAILURES" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 1 ]
}

@test "apply: an apply.sh that only warns is not a failed hook" {
  # The live case: git/apply.sh warns about an empty user.name and carries on
  # by design. Reported as "git: apply.sh failed", that sends you looking for
  # a broken hook that is working exactly as written.
  local m
  m=$(make_module demo)
  hook "$m" apply.sh 2

  module_apply demo
  [ "$DOT_FAILURES" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 1 ]
}

# --- A module whose packages will not install ---------------------------------

@test "apply: a failing Brewfile stops that module, not the run" {
  # The regression, and it needed a real `set -e` shell to see: brew_bundle
  # calls `fail` AND returns 1, and module_apply ran it bare -- so one
  # unavailable cask aborted `dot apply` where it stood. Every module after it
  # went unapplied, and the ERR trap blamed lib/modules.sh rather than naming
  # the package. "fail does not exit" has to hold here too.
  local a b
  a=$(make_module alpha)
  b=$(make_module beta)
  printf 'x\n' >"$b/home/.betarc"
  : "$a"

  run env -u DOT_ROOT bash -euo pipefail -c "
    source \"$BATS_TEST_DIRNAME/../lib/dot.sh\"
    DOT_ROOT='$REPO'
    brew_bundle() { fail 'the Brewfile failed'; return 1; }
    module_apply alpha
    module_apply beta
    echo REACHED-THE-END
  "
  # Both failures counted, so the run still exits non-zero...
  [ "$status" -eq 1 ]
  # ...but it got all the way to the end, and beta's files were still linked.
  [[ $output == *"REACHED-THE-END"* ]]
  [ -L "$HOME/.betarc" ]
}

@test "apply: apply.sh is skipped when its packages did not install" {
  # Brewfile -> links -> apply.sh is ordered so apply.sh can assume its
  # packages exist. Running it when they do not produces a second, more
  # confusing failure stacked on top of the real one. Files are still linked:
  # they depend on nothing but the repo.
  local m
  m=$(make_module demo)
  printf 'x\n' >"$m/home/.demorc"
  printf '#!/usr/bin/env bash\ntouch "$HOME/apply-ran"\n' >"$m/apply.sh"

  brew_bundle() {
    fail 'the Brewfile failed'
    return 1
  }
  module_apply demo

  [ ! -e "$HOME/apply-ran" ]
  [ -L "$HOME/.demorc" ]
  [ "$DOT_FAILURES" -eq 1 ]
}

@test "doctor: a status that is neither 0 nor the warn status is a failure" {
  # The fold must be narrow. If it treated "non-zero but not 1" as a warning,
  # every unexpected crash would be downgraded to a shrug.
  local m
  m=$(make_module demo)
  hook "$m" doctor.sh 3

  module_doctor demo
  [ "$DOT_FAILURES" -eq 1 ]
  [ "$DOT_WARNINGS" -eq 0 ]
}

# run_script BODY -- BODY in a fresh process with the real library loaded, the
# way a hook actually runs. `env -u DOT_ROOT` so lib/dot.sh derives the root
# from its own location rather than inheriting a fake one.
run_script() {
  run env -u DOT_ROOT bash -euo pipefail -c "
    source \"$BATS_TEST_DIRNAME/../lib/dot.sh\"
    $1
  "
}

@test "hooks: a script that warns and breaks nothing exits with the warn status" {
  run_script "warn 'something worth saying'"
  [ "$status" -eq 2 ]
}

@test "hooks: a script that warns AND fails exits 1" {
  # Failure outranks a warning. Otherwise a hook that did both would be folded
  # back in as a warning and the failure would disappear.
  run_script "warn 'noise'; fail 'the actual problem'"
  [ "$status" -eq 1 ]
}

@test "hooks: a script that says nothing still exits 0" {
  # The regression guard on the trap itself: the warn branch must not fire on
  # a clean run. An earlier version of this exit trap made every clean hook
  # report failure, which is the same mistake one status along.
  run_script "true"
  [ "$status" -eq 0 ]
}
