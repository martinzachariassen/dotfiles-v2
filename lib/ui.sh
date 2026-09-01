# shellcheck shell=bash
#
# Terminal output. This is the only place in the repo that emits colour or
# glyphs -- install.sh deliberately does not use it, because install.sh runs
# before the repo exists and a second copy of this file is exactly the kind of
# duplication v2 is built to avoid.

[[ -n ${__DOT_UI_SH:-} ]] && return 0
__DOT_UI_SH=1

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

heading() { printf '\n%s%s%s\n' "$__C_BOLD" "$*" "$__C_RESET"; }
say() { printf '  %s\n' "$*"; }
dim() { printf '  %s%s%s\n' "$__C_DIM" "$*" "$__C_RESET"; }
ok() { printf '  %s✓%s %s\n' "$__C_GREEN" "$__C_RESET" "$*"; }
info() { printf '  %s→%s %s\n' "$__C_BLUE" "$__C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$__C_YELLOW" "$__C_RESET" "$*" >&2; }

fail() {
  printf '  %s✗%s %s\n' "$__C_RED" "$__C_RESET" "$*" >&2
  DOT_FAILURES=$((DOT_FAILURES + 1))
}

# Unrecoverable: print and stop immediately.
die() {
  printf '  %s✗%s %s\n' "$__C_RED" "$__C_RESET" "$*" >&2
  exit 1
}
