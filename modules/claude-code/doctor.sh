#!/usr/bin/env bash
#
# Only checks what fails silently: a broken statusLine just renders nothing,
# and nobody is watching Claude Code's stderr.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Checked even though this module's Brewfile installs it: doctor reports on the
# machine as it is now, and a `brew uninstall jq` leaves the bar rendering
# nothing with no error printed anywhere.
command -v jq >/dev/null 2>&1 || fail 'jq is not installed -- statusline.sh depends on it (run: dot apply)'

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"
if [[ -f $dest ]]; then
  configured="$(jq -r '.statusLine.command // empty' "$dest" 2>/dev/null || true)"
  [[ $configured == "$script" ]] || fail "$dest .statusLine is not wired to $script"
fi
