# shellcheck shell=bash
#
# Terminal output. This is the only place in the repo that emits colour or
# glyphs -- install.sh deliberately does not use it, because install.sh runs
# before the repo exists and a second copy of this file is exactly the kind of
# duplication v2 is built to avoid.

# Colour only when stdout is a terminal and NO_COLOR is unset.
# https://no-color.org
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

# Failure tally. `fail` never exits on its own -- a doctor run should report
# every problem, not just the first. lib/dot.sh installs the EXIT trap that
# turns a non-zero tally into a non-zero exit status, so scripts that use
# these helpers never have to think about exit codes.
DOT_FAILURES=0

# Warning tally, and the exit status that carries it out of a hook.
#
# `warn` is for what is not wrong but is worth saying: an orphaned link, a
# stopped VM, an empty identity. Those must not change an exit status -- and
# they must not be drowned out either. `dot doctor` used to list them and then
# print "Everything looks right" underneath, which is how a report teaches you
# to stop reading it. So they are counted, and the Result line reads the count.
#
# A hook runs in its own bash process (see lib/modules.sh), so everything it
# found reaches its driver as a single number. 0 and 1 already mean clean and
# broken; DOT_STATUS_WARN is the third answer, folded back in by fold_status.
DOT_WARNINGS=0
DOT_STATUS_WARN=2

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
# The middle case is the whole reason this exists. A hook that only warned
# exits DOT_STATUS_WARN, and every call site had to guess what that meant:
# doctor's `|| true` read it as nothing and printed "Everything looks right"
# over a stopped colima, while apply's `if ! ...` read it as a crash and
# reported "git: apply.sh failed" for an empty user.name. One place decides.
#
# MESSAGE is used only when the child actually broke, because it has already
# printed its own detail either way -- this line says which hook it came from.
#
# The count is children-that-warned, not warnings-they-printed. That is why the
# Result line points at the warnings instead of numbering them.
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
