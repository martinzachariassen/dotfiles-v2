#!/usr/bin/env bash
#
# Point Claude Code's statusLine at the script home/ already linked into
# place, and merge in a baseline permissions floor.
#
# settings.json carries permissions, hooks and everything else the user has
# configured, so it is merged with jq rather than written whole -- the same
# shape as the git module's config.local, minus the "generated" header:
# settings.json is not this module's file to own, just one key inside it.
# A sibling data file for $allow/$deny would dodge the duplication below, but
# modules/CLAUDE.md closes the module directory to a fixed set of names --
# contract.bats fails any file that is not in it, on purpose.
#
# permissions.allow/.deny are merged additively (existing + baseline, deduped),
# never overwritten: an "Always allow" click in a session appends to these
# arrays, and a plain assignment here would silently discard that on the next
# `dot apply`. defaultMode uses //= for the same reason. doctor.sh and
# remove.sh embed the same $allow/$deny literals -- keep all three in sync.
#
# jq is not guarded for. It comes from this module's own Brewfile, and the
# driver skips apply.sh outright when a module's Brewfile fails -- that is the
# one promise module_apply makes. Before the cask moved here, jq was dev-cli's
# and this hook had to warn and skip, because dev-cli runs later.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"
allow='["Bash(git status)","Bash(git diff*)","Bash(git log*)","Bash(git show*)","Bash(git branch*)","Bash(ls*)","Bash(pwd)"]'
deny='["Bash(rm -rf *)","Bash(git push --force*)","Bash(git reset --hard*)","Bash(curl * | sh*)","Bash(curl * | bash*)","Read(~/.ssh/*)","Read(./.env)","Read(./.env.*)","Read(**/*.pem)","Read(**/id_rsa*)"]'

if [[ $DOT_DRY_RUN == 1 ]]; then
  info "write   ~/.claude/settings.json (.statusLine, .permissions)"
  exit 0
fi

mkdir -p "$(dirname "$dest")"
[[ -f $dest ]] || printf '{}' >"$dest"

tmp="$(mktemp "${dest}.XXXXXX")"
jq --arg cmd "$script" --argjson allow "$allow" --argjson deny "$deny" '
  .statusLine = {type: "command", command: $cmd, padding: 0}
  | .permissions.defaultMode //= "default"
  | .permissions.allow = ((.permissions.allow // []) + $allow | unique)
  | .permissions.deny  = ((.permissions.deny  // []) + $deny  | unique)
' "$dest" >"$tmp" && mv "$tmp" "$dest"

ok "Claude Code status line wired to $script, permissions floor applied"
