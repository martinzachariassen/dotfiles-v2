#!/usr/bin/env bash
# Claude Code status line: model · dir · git · context, one line.
#
# ANSI-16 colors only, no hardcoded hex, so the bar follows whatever terminal
# theme is active instead of fighting it. Icons are Nerd Font glyphs already
# used by starship's prompt on the line above -- the branch icon here is the
# same glyph modules/zsh/home/.config/starship.toml uses for git_branch, so it
# means the same thing in both places.
set -euo pipefail

input="$(cat)"

RESET=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m'
RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
BLUE=$'\033[34m' MAGENTA=$'\033[35m' CYAN=$'\033[36m'
SEP=" ${DIM}·${RESET} "

I_DIR=$''    # fa-folder
I_BRANCH=$'' # pl-branch -- matches starship's git_branch symbol
I_CTX=$'󰍛'   # md-memory

# 1234 -> 1k, 1000000 -> 1.0M.
fmt_tokens() {
  local n=$1
  if ((n >= 1000000)); then
    printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
  elif ((n >= 1000)); then
    printf '%dk' $((n / 1000))
  else
    printf '%d' "$n"
  fi
}

# Same 70/90 split as starship's own status coloring, so yellow means the same
# amount of trouble everywhere in the terminal.
pct_color() {
  if (($1 >= 90)); then
    printf '%s' "$RED"
  elif (($1 >= 70)); then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

trunc() {
  local max=$1 s=$2
  if ((${#s} > max)); then printf '%s…' "${s:0:max-1}"; else printf '%s' "$s"; fi
}

# One jq call: its startup cost dominates runtime, so every field comes out
# of a single pass with \037 (a byte that cannot appear in the values) as the
# join separator.
fields="$(jq -r '
    def clean: if . == null then "" else tostring end;
    [ (.model.display_name // "?" | clean),
      (.workspace.current_dir // "" | clean),
      (.session_id // "" | clean),
      (.context_window.used_percentage // 0 | floor | tostring),
      (.context_window.total_input_tokens // 0 | tostring),
      (.context_window.context_window_size // 0 | tostring)
    ] | join("")' <<<"$input")"
IFS=$'\037' read -r MODEL DIR SESSION_ID PCT USED_TOKENS CTX_SIZE <<<"$fields"
SESSION_ID=${SESSION_ID:-default}

OUT="${CYAN}${BOLD}${MODEL}${RESET}"

if [[ -n $DIR ]]; then
  D="$(trunc 30 "${DIR##*/}")"
  OUT+="${SEP}${DIM}${I_DIR}${RESET} ${BLUE}${BOLD}${D}${RESET}"
fi

# Cached per session for a few seconds: the bar re-renders on every keystroke,
# and `git status` is the slowest thing on this line in any repo of size.
if [[ -n $DIR ]] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  cache="${TMPDIR:-/tmp}/claude-statusline-git-${SESSION_ID}"
  age=999
  if [[ -f $cache ]]; then
    mtime=$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0)
    age=$(($(date +%s) - mtime))
  fi
  if ((age > 5)); then
    git -C "$DIR" status --porcelain=v2 --branch 2>/dev/null | awk '
            /^# branch.head / { head = $3 }
            /^[12] / {
                if (substr($2, 1, 1) != ".") staged++
                if (substr($2, 2, 1) != ".") modified++
            }
            /^u / { conflicts++ }
            /^\? / { untracked++ }
            END { printf "%s|%d|%d|%d|%d\n", head, staged+0, modified+0, untracked+0, conflicts+0 }
        ' >"$cache" || printf '||||\n' >"$cache"
  fi
  IFS='|' read -r BRANCH STAGED MODIFIED UNTRACKED CONFLICTS <"$cache"
  STAGED=${STAGED:-0} MODIFIED=${MODIFIED:-0} UNTRACKED=${UNTRACKED:-0} CONFLICTS=${CONFLICTS:-0}
  if [[ -n $BRANCH && $BRANCH != '(detached)' ]]; then
    B="$(trunc 32 "$BRANCH")"
    G="${DIM}${I_BRANCH}${RESET} ${MAGENTA}${B}${RESET}"
    ((STAGED > 0)) && G+=" ${GREEN}+${STAGED}${RESET}"
    ((MODIFIED > 0)) && G+=" ${YELLOW}!${MODIFIED}${RESET}"
    ((UNTRACKED > 0)) && G+=" ${BLUE}?${UNTRACKED}${RESET}"
    ((CONFLICTS > 0)) && G+=" ${RED}✗${CONFLICTS}${RESET}"
    OUT+="${SEP}${G}"
  fi
fi

if ((CTX_SIZE > 0)); then
  T="$(fmt_tokens "$USED_TOKENS")/$(fmt_tokens "$CTX_SIZE")"
  OUT+="${SEP}${DIM}${I_CTX}${RESET} $(pct_color "$PCT")${PCT}%${RESET} ${DIM}${T}${RESET}"
fi

printf '%s\n' "$OUT"
