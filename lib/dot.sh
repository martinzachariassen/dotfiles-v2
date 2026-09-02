# shellcheck shell=bash
#
# The single entrypoint for shared code. Everything -- bin/dot, every module
# apply.sh and doctor.sh, every test -- sources this one file and gets the
# whole library. There is no partial import.
#
# Comments in lib/ explain decisions, not bash syntax.

[[ -n ${__DOT_SH:-} ]] && return 0
__DOT_SH=1

# bin/dot re-execs into bash 5 before it gets here; this catches the entry
# points that bypass it -- a hook run by hand, bats. Without it the symptom is
# a syntax error in a file the reader never opened.
if ((BASH_VERSINFO[0] < 5)); then
  printf 'dotfiles needs bash 5 or newer; this is %s. Run: brew install bash\n' \
    "$BASH_VERSION" >&2
  exit 1
fi

# --- Repo root -------------------------------------------------------------
#
# An inherited DOT_ROOT always wins, and that is the normal case: the shim at
# ~/.local/bin/dot exports it and the module driver passes it to every hook, so
# one value flows through the whole run. The fallback derives it from this
# file's location with no symlink resolution -- the shim is generated rather
# than symlinked precisely so no readlink loop is needed (see core/apply.sh).
if [[ -z ${DOT_ROOT:-} ]]; then
  DOT_ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi
export DOT_ROOT

# Refused here rather than escaped at each use, because three places bake this
# path into a script they then generate or match: the shim (core/apply.sh), the
# throwaway uninstall.sh execs into, and the greps that recognise the shim as
# ours. A `"` in the path makes the throwaway a syntax error -- so you type
# `remove`, and Homebrew and the repo are both still there afterwards with no
# message saying why. A backtick or $( ) is worse: the generated script runs it.
# Escaping at every site would be one rule in three copies that must agree
# forever; refusing the path once is the version that cannot drift. Spaces and
# non-ASCII are fine and stay fine -- every use is already quoted.
if [[ $DOT_ROOT != "${DOT_ROOT//[\"\`\$\\]/}" || $DOT_ROOT == *$'\n'* ]]; then
  printf 'dotfiles: the repo path contains a character that cannot be quoted safely:\n  %s\nMove the checkout somewhere with no " ` $ \\ or newline in its path.\n' \
    "$DOT_ROOT" >&2
  exit 1
fi

# --- Paths -----------------------------------------------------------------
#
# Config is hand-edited and precious; state is regenerable. Separate trees mean
# "rm -rf the state dir" is never a question you have to think hard about.
DOT_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DOT_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
DOT_CONFIG=${DOT_CONFIG:-$DOT_CONFIG_HOME/dotfiles/config.toml}
DOT_STATE=${DOT_STATE:-$DOT_STATE_HOME/dotfiles}
export DOT_CONFIG DOT_STATE

# When 1, every mutating helper prints what it would do and changes nothing.
# Read-only work still happens, so a dry run reports accurate drift.
DOT_DRY_RUN=${DOT_DRY_RUN:-0}
export DOT_DRY_RUN

# One id per run, inherited by every hook the run executes -- which is what
# makes "this run's backup directory" answerable from more than one process.
# Hooks are separate processes, so no variable the driver memoises can reach
# them: a file moved aside inside containers/apply.sh went into a directory of
# its own, and the driver's report named a different one, or none. See
# fs_backup_dir.
DOT_RUN_ID=${DOT_RUN_ID:-$(date +%Y%m%d-%H%M%S)}
export DOT_RUN_ID

# --- Library ---------------------------------------------------------------
source "$DOT_ROOT/lib/ui.sh"
source "$DOT_ROOT/lib/config.sh"
source "$DOT_ROOT/lib/fs.sh"
source "$DOT_ROOT/lib/brew.sh"
source "$DOT_ROOT/lib/modules.sh"
source "$DOT_ROOT/lib/wizard.sh"

# --- Failure reporting -----------------------------------------------------
#
# A module hook runs in its own process, so without this a crash is an exit
# code and nothing else. One line, and it stays one line -- for more, hooks are
# ordinary scripts: `bash -x modules/git/apply.sh`.
#
#   ✗ lib/fs.sh:114: mv "$dst" "$backup" (exit 1)
__DOT_REPORTED=0
__dot_on_err() {
  # All four captured first: the guards below are themselves commands, and
  # running them overwrites BASH_COMMAND. BASH_SOURCE[1]/BASH_LINENO[0] are the
  # frame that failed; index 0 is this handler.
  local status=$? cmd=$BASH_COMMAND src=${BASH_SOURCE[1]} line=${BASH_LINENO[0]}
  # errtrace fires this inside $( ) too, where toml_get probes for a missing
  # key -- without this guard every config default reported a failure.
  ((BASH_SUBSHELL == 0)) || return 0
  # The trap fires again at each frame as the stack unwinds.
  ((__DOT_REPORTED)) && return 0
  __DOT_REPORTED=1
  printf '  %s✗ %s:%s: %s (exit %s)%s\n' \
    "$__C_RED" "${src#"$DOT_ROOT"/}" "$line" "$cmd" "$status" "$__C_RESET" >&2
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
# problem in one pass. This turns the tally into an exit code, which means no
# script in the repo propagates one by hand.
#
# The status must be captured on the first line. Inline as
# `[[ $DOT_FAILURES -gt 0 ]] && exit 1; exit $?` it looks equivalent and is
# not: a false test leaves the && list at 1, so every clean hook "failed".
#
# A hook that only warned exits DOT_STATUS_WARN -- the one channel a separate
# process has for "nothing broken, but I said something". bin/dot and
# uninstall.sh clear __DOT_EXIT_WARN because they are nobody's hook: at the top
# level `dot doctor && ...` has to keep working when a link is orphaned.
__dot_on_exit() {
  local status=$?
  if [[ ${DOT_FAILURES:-0} -gt 0 ]]; then
    exit 1
  fi
  if ((status == 0 && ${DOT_WARNINGS:-0} > 0 && ${__DOT_EXIT_WARN:-1})); then
    exit "$DOT_STATUS_WARN"
  fi
  exit "$status"
}

# Only for scripts that have not already set their own EXIT trap.
if [[ -z $(trap -p EXIT) ]]; then
  trap __dot_on_exit EXIT
fi
