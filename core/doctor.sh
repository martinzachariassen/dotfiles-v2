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
  if grep -q "DOT_ROOT=\"$DOT_ROOT\"" "$shim" 2>/dev/null; then
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

# --- The repo is where the config thinks it is ------------------------------
#
# Not used for path resolution -- DOT_ROOT is always derived from this file's
# own location. This catches the case where you cloned the repo twice and are
# editing one copy while a different one is linked into $HOME.
declared=$(cfg_get 'core.repo' '')
if [[ -n $declared && $declared != "$DOT_ROOT" ]]; then
  fail "repo        config says $declared, running from $DOT_ROOT"
else
  ok "repo        $DOT_ROOT"
fi

# --- Uncommitted work -------------------------------------------------------
if git -C "$DOT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -n $(git -C "$DOT_ROOT" status --porcelain) ]]; then
    warn 'git         uncommitted changes in the repo'
  else
    ok 'git         clean'
  fi
fi
