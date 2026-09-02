#!/usr/bin/env bash
#
# Point Claude Code's statusLine at the script home/ already linked into
# place.
#
# settings.json carries permissions, hooks and everything else the user has
# configured, so it is merged with jq rather than written whole -- the same
# shape as the git module's config.local, minus the "generated" header:
# settings.json is not this module's file to own, just one key inside it.
#
# jq is not guarded for. It comes from this module's own Brewfile, and the
# driver skips apply.sh outright when a module's Brewfile fails -- that is the
# one promise module_apply makes. Before the cask moved here, jq was dev-cli's
# and this hook had to warn and skip, because dev-cli runs later.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info "write   ~/.claude/settings.json (.statusLine)"
  exit 0
fi

mkdir -p "$(dirname "$dest")"
[[ -f $dest ]] || printf '{}' >"$dest"

tmp="$(mktemp "${dest}.XXXXXX")"
jq --arg cmd "$script" \
  '.statusLine = {type: "command", command: $cmd, padding: 0}' \
  "$dest" >"$tmp" && mv "$tmp" "$dest"

ok "Claude Code status line wired to $script"
