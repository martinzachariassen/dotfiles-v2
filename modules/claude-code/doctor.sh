#!/usr/bin/env bash
#
# A broken statusLine renders nothing; a missing deny entry is a floor gone
# with no error. A missing allow entry just costs a prompt, so it is not checked.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

command -v jq >/dev/null 2>&1 || fail 'jq is not installed -- statusline.sh depends on it (run: dot apply)'

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"
# Must match apply.sh (tests/contract.bats).
deny='["Bash(rm -rf *)","Bash(git push --force*)","Bash(git reset --hard*)","Bash(curl * | sh*)","Bash(curl * | bash*)","Read(~/.ssh/**)","Read(~/.aws/**)","Read(~/.gnupg/**)","Read(~/.config/gh/**)","Read(./.env)","Read(./.env.*)"]'

if [[ -f $dest ]]; then
  configured="$(jq -r '.statusLine.command // empty' "$dest" 2>/dev/null || true)"
  [[ $configured == "$script" ]] || fail "$dest .statusLine is not wired to $script"

  missing=$(jq --argjson deny "$deny" '($deny - (.permissions.deny // [])) | length' "$dest" 2>/dev/null || echo 0)
  [[ $missing == 0 ]] || fail "$dest is missing $missing of this module's permissions.deny entries -- run: dot apply"
fi
