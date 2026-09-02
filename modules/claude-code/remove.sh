#!/usr/bin/env bash
#
# Undo the settings.json edit apply.sh makes. The script itself needs no
# cleanup here -- it is a home/ symlink, and the generic sweep in
# uninstall.sh already removes any link that points into this repo.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
script="$HOME/.claude/statusline.sh"

[[ -f $dest ]] || exit 0

current="$(jq -r '.statusLine.command // empty' "$dest" 2>/dev/null || true)"
if [[ $current == "$script" ]]; then
  tmp="$(mktemp "${dest}.XXXXXX")"
  jq 'del(.statusLine)' "$dest" >"$tmp" && mv "$tmp" "$dest"
  ok "removed .statusLine from ~/.claude/settings.json"
else
  warn 'left alone  ~/.claude/settings.json (.statusLine not set by this module)'
fi
