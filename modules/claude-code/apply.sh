#!/usr/bin/env bash
#
# Wire the statusLine and merge a permissions floor into settings.json.
#
# Merged with jq, never written whole: settings.json is the user's file. The
# allow/deny arrays are unioned so an "Always allow" click survives the next
# apply. $allow/$deny are duplicated in doctor.sh and remove.sh -- a sibling
# data file is not allowed by the module contract -- and tests/contract.bats
# asserts the three copies agree.
#
# Every Read deny rule is anchored to one directory or one file. An any-depth
# filename glob (Read(**/*.pem)) makes every recursive grep a possible hit, so
# auto mode escalates each one to the user -- and it still misses the same file
# outside cwd, and any subprocess that opens it directly. Wildcard secrets
# belong in sandbox.filesystem.denyRead, which the OS enforces.
#
# spinnerTipsEnabled uses //=, not =: unlike statusLine there is no unique
# value that proves the module set it, so remove.sh leaves it alone and apply.sh
# only sets the default once -- a user who re-enables tips stays re-enabled.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"
allow='["Bash(git status)","Bash(git diff*)","Bash(git log*)","Bash(git show*)","Bash(git branch*)","Bash(ls*)","Bash(pwd)"]'
deny='["Bash(rm -rf *)","Bash(git push --force*)","Bash(git reset --hard*)","Bash(curl * | sh*)","Bash(curl * | bash*)","Read(~/.ssh/**)","Read(~/.aws/**)","Read(~/.gnupg/**)","Read(~/.config/gh/**)","Read(./.env)","Read(./.env.*)"]'

if [[ $DOT_DRY_RUN == 1 ]]; then
  info "write   ~/.claude/settings.json (.statusLine, .permissions, .spinnerTipsEnabled)"
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
  | .spinnerTipsEnabled //= false
' "$dest" >"$tmp" && mv "$tmp" "$dest"

ok "Claude Code status line wired to $script, permissions floor applied, tips disabled"
