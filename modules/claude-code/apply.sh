#!/usr/bin/env bash
#
# Point Claude Code's statusLine at the script home/ already linked into
# place.
#
# settings.json carries permissions, hooks and everything else the user has
# configured, so it is merged with jq rather than written whole -- the same
# shape as the git module's config.local, minus the "generated" header:
# settings.json is not this module's file to own, just one key inside it.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info "write   ~/.claude/settings.json (.statusLine)"
  exit 0
fi

# jq itself is owned by dev-cli, not this module. Modules run alphabetically,
# so on a machine that has never run `dot apply`, claude-code goes before
# dev-cli and jq may not exist yet -- the recoverable half of that is to skip
# and say so, the same shape as git/apply.sh waiting on 1Password.
if ! command -v jq >/dev/null 2>&1; then
  warn 'jq is not installed yet -- re-run `dot apply` to wire the status line'
  exit 0
fi

mkdir -p "$(dirname "$dest")"
[[ -f $dest ]] || printf '{}' >"$dest"

tmp="$(mktemp "${dest}.XXXXXX")"
jq --arg cmd "$script" \
  '.statusLine = {type: "command", command: $cmd, padding: 0}' \
  "$dest" >"$tmp" && mv "$tmp" "$dest"

ok "Claude Code status line wired to $script"
