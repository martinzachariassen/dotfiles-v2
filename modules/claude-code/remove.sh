#!/usr/bin/env bash
#
# Undo apply.sh's settings.json edits. Only this module's exact entries are
# subtracted; anything added since is left standing. The script itself is a
# home/ symlink and goes with the generic sweep.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"
# Must match apply.sh (tests/contract.bats).
allow='["Bash(git status)","Bash(git diff*)","Bash(git log*)","Bash(git show*)","Bash(git branch*)","Bash(ls*)","Bash(pwd)"]'
deny='["Bash(rm -rf *)","Bash(git push --force*)","Bash(git reset --hard*)","Bash(curl * | sh*)","Bash(curl * | bash*)","Read(~/.ssh/**)","Read(~/.aws/**)","Read(~/.gnupg/**)","Read(~/.config/gh/**)","Read(./.env)","Read(./.env.*)"]'

[[ -f $dest ]] || exit 0

current="$(jq -r '.statusLine.command // empty' "$dest" 2>/dev/null || true)"
if [[ $current == "$script" ]]; then
  tmp="$(mktemp "${dest}.XXXXXX")"
  jq 'del(.statusLine)' "$dest" >"$tmp" && mv "$tmp" "$dest"
  ok "removed .statusLine from ~/.claude/settings.json"
else
  warn 'left alone  ~/.claude/settings.json (.statusLine not set by this module)'
fi

tmp="$(mktemp "${dest}.XXXXXX")"
jq --argjson allow "$allow" --argjson deny "$deny" '
  .permissions.allow = ((.permissions.allow // []) - $allow)
  | .permissions.deny  = ((.permissions.deny  // []) - $deny)
' "$dest" >"$tmp" && mv "$tmp" "$dest"
ok "removed this module's baseline entries from .permissions.allow/.deny"
