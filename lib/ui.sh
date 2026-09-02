# shellcheck shell=bash
#
# Terminal output. The only place in the repo that emits colour or glyphs --
# install.sh deliberately does not use it, because it runs before the repo
# exists and a second copy of this file is the duplication v2 exists to avoid.

# Colour only when stdout is a terminal and NO_COLOR is unset (no-color.org).
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  __C_RESET=$'\033[0m'
  __C_DIM=$'\033[2m'
  __C_BOLD=$'\033[1m'
  __C_RED=$'\033[31m'
  __C_GREEN=$'\033[32m'
  __C_YELLOW=$'\033[33m'
  __C_BLUE=$'\033[34m'
else
  __C_RESET='' __C_DIM='' __C_BOLD='' __C_RED='' __C_GREEN='' __C_YELLOW='' __C_BLUE=''
fi

# Failure tally. `fail` never exits: a doctor run reports every problem, not
# just the first. lib/dot.sh turns a non-zero tally into a non-zero exit
# status, so nothing using these helpers thinks about exit codes.
DOT_FAILURES=0

# Warning tally, and the exit status that carries it out of a hook.
#
# `warn` is for what is not wrong but is worth saying: an orphaned link, a
# stopped VM, an empty identity. Those must not change an exit status, and they
# must not be drowned out either -- `dot doctor` used to list them and then
# print "Everything looks right" underneath. So they are counted and the Result
# line reads the count.
#
# A hook runs in its own process, so what it found reaches its driver as a
# single number. 0 and 1 already mean clean and broken; DOT_STATUS_WARN is the
# third answer, folded back in by fold_status.
#
# 3, AND NOT 2, WHICH IS WHAT IT USED TO BE. bash exits 2 on a syntax error --
# a hook with a typo in it, which executed nothing at all -- so every driver
# read a script that never ran as "finished, with something worth mentioning".
# The worst of the five call sites is module_remove: uninstall.sh refuses to
# hand off to the irreversible half while DOT_FAILURES is non-zero, and a
# warning does not bump it. A mistyped remove.sh therefore contributed nothing
# to that guard, and the run went on to zap every cask, uninstall Homebrew and
# delete the repo with the module's cleanup never having happened. It was also
# invisible: macos-defaults/remove.sh exits WARN deliberately, so warnings
# during an uninstall look normal.
#
# 3 is the lowest status bash claims no meaning for -- 0, 1 and 2 are taken,
# and 126/127/128+n are the exec and signal range. Any number can still collide
# with whatever a hook's last command happened to return; the point is that it
# no longer collides with the interpreter itself.
DOT_WARNINGS=0
DOT_STATUS_WARN=3

heading() { printf '\n%s%s%s\n' "$__C_BOLD" "$*" "$__C_RESET"; }
say() { printf '  %s\n' "$*"; }
dim() { printf '  %s%s%s\n' "$__C_DIM" "$*" "$__C_RESET"; }
ok() { printf '  %s✓%s %s\n' "$__C_GREEN" "$__C_RESET" "$*"; }
info() { printf '  %s→%s %s\n' "$__C_BLUE" "$__C_RESET" "$*"; }
warn() {
  printf '  %s!%s %s\n' "$__C_YELLOW" "$__C_RESET" "$*" >&2
  DOT_WARNINGS=$((DOT_WARNINGS + 1))
}

fail() {
  printf '  %s✗%s %s\n' "$__C_RED" "$__C_RESET" "$*" >&2
  DOT_FAILURES=$((DOT_FAILURES + 1))
}

# fold_status MESSAGE CMD... -- run CMD, which is or wraps a separate process,
# and fold what it found back into this process's tallies.
#
# The middle case is why this exists. Every call site used to guess what
# DOT_STATUS_WARN meant: doctor's `|| true` read it as nothing and printed
# "Everything looks right" over a stopped colima, while apply's `if ! ...` read
# it as a crash and reported "git: apply.sh failed" for an empty user.name.
#
# MESSAGE is used only when the child actually broke -- it has printed its own
# detail either way, so this line only says which hook it came from.
fold_status() {
  local msg=$1 status=0
  shift
  "$@" || status=$?
  case $status in
    0) ;;
    "$DOT_STATUS_WARN") DOT_WARNINGS=$((DOT_WARNINGS + 1)) ;;
    *) fail "$msg" ;;
  esac
}

# Unrecoverable: print and stop immediately.
die() {
  printf '  %s✗%s %s\n' "$__C_RED" "$__C_RESET" "$*" >&2
  exit 1
}
