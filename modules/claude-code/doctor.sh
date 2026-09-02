#!/usr/bin/env bash
#
# Only checks what fails silently: a broken statusLine just renders nothing,
# and a missing deny entry is a security floor gone with no error anywhere --
# both need doctor. A missing allow entry just costs an extra prompt, which is
# loud by construction, so it is not checked here.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Checked even though this module's Brewfile installs it: doctor reports on the
# machine as it is now, and a `brew uninstall jq` leaves the bar rendering
# nothing with no error printed anywhere.
command -v jq >/dev/null 2>&1 || fail 'jq is not installed -- statusline.sh depends on it (run: dot apply)'

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"
# Must match apply.sh's $deny.
deny='["Bash(rm -rf *)","Bash(git push --force*)","Bash(git reset --hard*)","Bash(curl * | sh*)","Bash(curl * | bash*)","Read(~/.ssh/*)","Read(./.env)","Read(./.env.*)","Read(**/*.pem)","Read(**/id_rsa*)"]'

if [[ -f $dest ]]; then
  configured="$(jq -r '.statusLine.command // empty' "$dest" 2>/dev/null || true)"
  [[ $configured == "$script" ]] || fail "$dest .statusLine is not wired to $script"

  missing=$(jq --argjson deny "$deny" '($deny - (.permissions.deny // [])) | length' "$dest" 2>/dev/null || echo 0)
  [[ $missing == 0 ]] || fail "$dest is missing $missing of this module's permissions.deny entries -- run: dot apply"
fi
