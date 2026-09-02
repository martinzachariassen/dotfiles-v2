#!/usr/bin/env bash
#
# Only checks what fails silently: a broken statusLine just renders nothing,
# and nobody is watching Claude Code's stderr.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# jq ships with dev-cli, not this module -- see the Brewfile comment there.
command -v jq >/dev/null 2>&1 || fail 'jq is not installed -- statusline.sh depends on it (dev-cli module)'

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"
if [[ -f $dest ]]; then
  configured="$(jq -r '.statusLine.command // empty' "$dest" 2>/dev/null || true)"
  [[ $configured == "$script" ]] || fail "$dest .statusLine is not wired to $script"
fi
