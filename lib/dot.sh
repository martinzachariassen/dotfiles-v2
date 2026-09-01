# shellcheck shell=bash
#
# The single entrypoint for shared code. Everything -- bin/dot, every module
# apply.sh and doctor.sh, every test -- sources this one file and gets the
# whole library. There is no partial import.

[[ -n ${__DOT_SH:-} ]] && return 0
__DOT_SH=1

# --- Repo root -------------------------------------------------------------
#
# An inherited DOT_ROOT always wins. That is the normal case: the shim at
# ~/.local/bin/dot exports it, and the module driver passes it to every hook,
# so a single value flows through the whole run.
#
# The fallback derives it from this file's location, with no symlink
# resolution -- deliberately. ~/.local/bin/dot is a generated shim rather than
# a symlink precisely so that no readlink loop is needed here or in bin/dot.
# See core/apply.sh for why.
if [[ -z ${DOT_ROOT:-} ]]; then
  DOT_ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi
export DOT_ROOT

# --- Paths -----------------------------------------------------------------
#
# Config is hand-edited and precious. State is regenerable and safe to delete.
# Keeping them in separate trees means "rm -rf the state dir" is never a
# question you have to think hard about.
DOT_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DOT_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
DOT_CONFIG=${DOT_CONFIG:-$DOT_CONFIG_HOME/dotfiles/config.toml}
DOT_STATE=${DOT_STATE:-$DOT_STATE_HOME/dotfiles}
export DOT_CONFIG DOT_STATE

# When set to 1, every mutating helper prints what it would do and changes
# nothing. Read-only work happens for real either way, so a dry run still
# reports accurate drift.
DOT_DRY_RUN=${DOT_DRY_RUN:-0}
export DOT_DRY_RUN

# --- Library ---------------------------------------------------------------
source "$DOT_ROOT/lib/ui.sh"
source "$DOT_ROOT/lib/config.sh"
source "$DOT_ROOT/lib/fs.sh"
source "$DOT_ROOT/lib/brew.sh"
source "$DOT_ROOT/lib/modules.sh"
source "$DOT_ROOT/lib/wizard.sh"

# --- Failure reporting -----------------------------------------------------
#
# A module hook runs in its own bash process, so without this a crash is an
# exit code and nothing else. One line: file, command, status. For more,
# hooks are ordinary scripts -- `bash -x modules/git/apply.sh`.
#
# No line number: for a failure inside a function bash 3.2 reports the
# function's DEFINITION line, not the failing one, and a wrong number costs
# more than no number.
__DOT_REPORTED=0
__dot_on_err() {
  # All three captured first: the guards below are themselves commands, and
  # running them overwrites BASH_COMMAND.
  local status=$? cmd=$BASH_COMMAND src=${BASH_SOURCE[1]}
  # errtrace fires this inside $( ) too, where toml_get probes for a missing
  # key -- without this every config default reported a failure.
  ((BASH_SUBSHELL == 0)) || return 0
  # The trap fires again at each frame as the stack unwinds.
  ((__DOT_REPORTED)) && return 0
  __DOT_REPORTED=1
  printf '  %s✗ %s: %s (exit %s)%s\n' \
    "$__C_RED" "${src#"$DOT_ROOT"/}" "$cmd" "$status" "$__C_RESET" >&2
  return 0
}

# Not for a shell that already has an ERR trap: bats installs one, and stomping
# on it made the runner report this instead of the failing assertion.
if [[ -z $(trap -p ERR) ]]; then
  set -o errtrace
  trap __dot_on_err ERR
fi

# --- Exit status -----------------------------------------------------------
#
# `fail` bumps DOT_FAILURES rather than exiting, so a doctor run reports every
# problem in one pass. This turns the tally into an exit code at the end,
# which means no script in the repo has to propagate one by hand.
#
# The status must be captured on the trap's first line. Writing this inline as
# `[[ $DOT_FAILURES -gt 0 ]] && exit 1; exit $?` looks equivalent and is not:
# when the test is false the && list itself returns 1, so $? is 1 and every
# clean hook "fails". That bug made `bash core/apply.sh` exit 1 on success.
__dot_on_exit() {
  local status=$?
  if [[ ${DOT_FAILURES:-0} -gt 0 ]]; then
    exit 1
  fi
  exit "$status"
}

# Only installed for scripts that have not already set their own EXIT trap.
if [[ -z $(trap -p EXIT) ]]; then
  trap __dot_on_exit EXIT
fi
