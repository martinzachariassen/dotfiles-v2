#!/usr/bin/env bash
#
# Core health checks. Read-only, always.
#
# This is not a privileged built-in -- it is simply the first doctor script to
# run, with the same contract as any module's. That symmetry is what keeps
# "core is just a module" true rather than aspirational.
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
if [[ -x $shim ]]; then
  # -F: a checkout path is a literal, not a pattern -- an unescaped `.` would
  # match anything and a `[` would be a syntax error inside a health check.
  if grep -qF "DOT_ROOT=\"$DOT_ROOT\"" "$shim" 2>/dev/null; then
    ok 'dot         installed'
  else
    fail 'dot         ~/.local/bin/dot points at a different checkout'
  fi
else
  fail 'dot         not installed in ~/.local/bin (run: dot apply)'
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok 'PATH        includes ~/.local/bin' ;;
  *) fail 'PATH        missing ~/.local/bin (enable the zsh module, or add it)' ;;
esac

# --- Config parses ----------------------------------------------------------
if cfg_exists; then
  if dasel -i toml -o json 'schema' <"$DOT_CONFIG" >/dev/null 2>&1; then
    ok "config      ${DOT_CONFIG/#$HOME/\~}"
  else
    fail "config      ${DOT_CONFIG/#$HOME/\~} does not parse as TOML"
  fi
else
  fail "config      missing (run: dot config --init)"
fi

ok "repo        $DOT_ROOT"

# --- Uncommitted work -------------------------------------------------------
if git -C "$DOT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -n $(git -C "$DOT_ROOT" status --porcelain) ]]; then
    # `dim`, not `warn`, and the demotion is the point. Warnings now reach the
    # Result line, and this one is true on every machine the repo is edited on
    # -- it would have left the summary permanently yellow, which is the same
    # bug as leaving it permanently green. It is also not a check by this
    # repo's own rule: nothing here fails silently, `git status` says it too.
    dim 'git         uncommitted changes in the repo'
  else
    ok 'git         clean'
  fi
fi
