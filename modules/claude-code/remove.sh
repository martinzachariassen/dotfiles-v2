#!/usr/bin/env bash
#
# Undo the settings.json edits apply.sh makes. The script itself needs no
# cleanup here -- it is a home/ symlink, and the generic sweep in
# uninstall.sh already removes any link that points into this repo.
#
# permissions.allow/.deny: only the exact entries this module added are
# subtracted, so anything added since -- by hand, or an "Always allow" click
# in a session -- is left standing. Must match apply.sh's $allow/$deny.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"
allow='["Bash(git status)","Bash(git diff*)","Bash(git log*)","Bash(git show*)","Bash(git branch*)","Bash(ls*)","Bash(pwd)"]'
deny='["Bash(rm -rf *)","Bash(git push --force*)","Bash(git reset --hard*)","Bash(curl * | sh*)","Bash(curl * | bash*)","Read(~/.ssh/*)","Read(./.env)","Read(./.env.*)","Read(**/*.pem)","Read(**/id_rsa*)"]'

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
