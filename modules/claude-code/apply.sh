#!/usr/bin/env bash
#
# Wire the statusLine and merge a permissions floor into settings.json.
#
# Merged with jq, never written whole: settings.json is the user's file. The
# allow/deny arrays are unioned so an "Always allow" click survives the next
# apply. $allow/$deny are duplicated in doctor.sh and remove.sh -- a sibling
# data file is not allowed by the module contract -- and tests/contract.bats
# asserts the three copies agree.
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
