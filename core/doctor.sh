#!/usr/bin/env bash
#
# Core health checks. Read-only, always. Not a privileged built-in -- just the
# first doctor script to run, under the same contract as any module's.
#
# A check earns its place only if the thing it checks fails SILENTLY. "Is git
# installed" is not a check; you would notice. "Is ~/.local/bin on PATH" is,
# because the symptom is a command that mysteriously does not exist.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# --- Homebrew ---------------------------------------------------------------
if brew_load; then
  ok "homebrew    $(brew --prefix)"
else
  fail 'homebrew    not found'
fi

# --- The CLI can actually be invoked ----------------------------------------
shim="$HOME/.local/bin/dot"
if [[ ! -f $shim ]]; then
  fail 'dot         not installed in ~/.local/bin (run: dot apply)'
elif [[ ! -x $shim ]]; then
  # Its own branch, not folded into "not installed" -- that sends you hunting
  # for a file already sitting there. (uninstall.sh tests -f rather than -x on
  # purpose: a shim that lost the bit is still ours to remove.)
  fail 'dot         ~/.local/bin/dot is not executable (run: dot apply)'
# -F: a checkout path is a literal, not a pattern -- an unescaped `.` would
# match anything and a `[` would be a syntax error inside a health check.
elif grep -qF "DOT_ROOT=\"$DOT_ROOT\"" "$shim" 2>/dev/null; then
  ok 'dot         installed'
else
  fail 'dot         ~/.local/bin/dot points at a different checkout'
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok 'PATH        includes ~/.local/bin' ;;
  *) fail 'PATH        missing ~/.local/bin (enable the zsh module, or add it)' ;;
esac

# --- Config parses ----------------------------------------------------------
#
# This used to ask dasel for `schema`, which the generator writes above every
# line a user would edit -- so the check passed on a config dasel had given up
# on halfway through. See cfg_parse_problems for what that costs.
if cfg_exists; then
  problems=$(cfg_parse_problems)
  if [[ -z $problems ]]; then
    ok "config      ${DOT_CONFIG/#$HOME/\~}"
  else
    while IFS= read -r problem; do
      fail "config      $problem"
    done <<<"$problems"
  fi
else
  fail "config      missing (run: dot config --init)"
fi

ok "repo        $DOT_ROOT"

# --- Uncommitted work -------------------------------------------------------
if git -C "$DOT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -n $(git -C "$DOT_ROOT" status --porcelain) ]]; then
    # `dim`, not `warn`, and the demotion is the point: warnings reach the
    # Result line, and this is true on every machine the repo is edited on. A
    # permanently yellow summary is the same bug as a permanently green one.
    dim 'git         uncommitted changes in the repo'
  else
    ok 'git         clean'
  fi
fi
