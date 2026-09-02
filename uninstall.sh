#!/usr/bin/env bash
#
# Phase 0 in reverse: put this machine back roughly the way install.sh found it.
#
#   bash uninstall.sh --dry-run    print every intended change, make none
#   bash uninstall.sh              do it
#
# WHY THIS IS NOT `dot uninstall`. bin/dot is capped at three verbs, and that
# cap is one of the shape rules holding this repo together -- see CLAUDE.md,
# "hard limits". Spending it here would also file the most destructive thing
# the repo can do under the command you type every day. install.sh is what
# brought this machine up from nothing; its opposite belongs next to it, and
# the symmetry is load-bearing rather than decorative: install.sh ends by
# exec'ing INTO the repo, and this ends by exec'ing OUT of it.
#
# WHAT IT DELIBERATELY DOES NOT TOUCH:
#
#   Xcode Command Line Tools -- macOS developer plumbing, not something this
#   repo chose to install on your behalf.
#
#   The backup tree under $DOT_STATE -- your own files, moved aside by an
#   earlier apply because they were in the way. Nothing else has a copy of
#   them, and "an apply never deletes" would be a promise good only until the
#   next command if an uninstall threw them away.
#
#   Real files in $HOME -- only symlinks into this repo, and the handful of
#   files it generated and can prove it generated, are removed.
#
#   macOS system preferences -- see modules/macos-defaults/remove.sh for why
#   they cannot be put back, and what would have to change for that to work.
#

# The repo targets bash 5 and macOS still ships 3.2 as /bin/bash. Same re-exec
# as bin/dot, for the same reason: the symptom otherwise is a syntax error deep
# inside a library file the reader did not open.
if ((BASH_VERSINFO[0] < 5)); then
  if [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "$0" "$@"
  fi
  echo "uninstall.sh needs bash 5 or newer; this is $BASH_VERSION." >&2
  exit 1
fi

set -euo pipefail

# shellcheck source=lib/dot.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/dot.sh"

# This is the top level, not somebody's hook. A warning here is information for
# the person reading -- a kept backup tree, a link that belongs to someone else
# -- and must not turn a completed uninstall into a non-zero exit.
__DOT_EXIT_WARN=0

BREW_UNINSTALL='https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh'

# Matched exactly, and anything else is fatal: `--dry` is a plausible typo, and
# this is the one script in the repo where silently ignoring it is unforgivable.
while (($#)); do
  case $1 in
    --dry-run) DOT_DRY_RUN=1 ;;
    *) die "unknown option '$1'. Try: bash uninstall.sh [--dry-run]" ;;
  esac
  shift
done
export DOT_DRY_RUN

[[ $(uname -s) == Darwin ]] || die 'This is macOS only.'
(($(id -u) != 0)) || die 'Do not run this as root.'

# --- Confirmation ------------------------------------------------------------
#
# The preview is this same script with --dry-run, not a summary written by hand
# alongside it. A hand-written one is a second description of the same work,
# and two descriptions drift -- the whole reason fs_link announces its intent
# before acting rather than after. Running the real code path with every
# mutating helper turned into a printf cannot disagree with the real run.
if [[ $DOT_DRY_RUN != 1 ]]; then
  [[ -t 0 ]] ||
    die 'Refusing to run unattended. Use --dry-run to see the plan.'

  "$BASH" "$0" --dry-run || die 'The preview failed; nothing was changed.'

  # No second description of the work. Summarising the preview in prose here is
  # how the old wording -- "every package it installed" -- came to say something
  # narrower than what the preview above had just counted.
  heading 'Confirm'
  say 'Everything listed above will be removed, and there is no undo.'
  printf '  Type %sremove%s to continue: ' "$__C_BOLD" "$__C_RESET"
  # `|| answer=''` so Ctrl-D lands on the same line as typing anything else.
  # Bare, it tripped errexit and answered the most destructive prompt in the
  # repo with a crash report instead of "Nothing was changed."
  read -r answer || answer=''
  [[ $answer == remove ]] || die 'Nothing was changed.'
fi

# --- Modules ------------------------------------------------------------------
#
# Every module in the repo, enabled or not -- modules_all, not modules_enabled.
# See module_remove in lib/modules.sh for why the hook exists at all.
while IFS= read -r name; do
  [[ -f "$(modules_dir "$name")/remove.sh" ]] || continue
  heading "Module: $name"
  module_remove "$name"
done < <(modules_all)

# --- Links ---------------------------------------------------------------------
#
# fs_repo_links is fs_orphans with the claiming half taken off: during an
# uninstall nothing is enabled, so every link into the repo is unclaimed by
# definition. Same walk, same filter, so the two verbs can never disagree about
# which links belong to this repo.
heading 'Links'
mapfile -t links < <(fs_repo_links)
if ((${#links[@]})); then
  for link in "${links[@]}"; do
    fs_unlink "$link"
  done
else
  say 'None found.'
fi

# --- The CLI shim ---------------------------------------------------------------
#
# Generated by core/apply.sh, not linked, so the sweep above cannot see it. The
# repo path baked into it is the proof of ownership -- core/doctor.sh already
# greps for this exact line to catch a shim pointing at a different checkout,
# and here the same test decides whether the file is ours to delete.
heading 'CLI'
shim="$HOME/.local/bin/dot"
# -f, where core/doctor.sh tests -x. Deliberate: a shim that lost its executable
# bit is broken there and still ours here, and skipping it would leave a dead
# `dot` on the PATH after an uninstall.
if [[ -f $shim ]]; then
  if grep -qF "DOT_ROOT=\"$DOT_ROOT\"" "$shim" 2>/dev/null; then
    fs_discard "$shim"
  else
    warn 'left alone  ~/.local/bin/dot points at a different checkout'
  fi
else
  say 'Not installed.'
fi

# --- Config ----------------------------------------------------------------------
# The existence test is here rather than left to fs_discard, which is silent
# about a missing file on purpose. A heading with nothing under it reads as
# something that went wrong quietly, which is the one thing a report of
# deletions must never do.
heading 'Config'
if [[ -f $DOT_CONFIG ]]; then
  fs_discard "$DOT_CONFIG"
  # rmdir rather than rm -rf: the directory goes only if this repo's config was
  # the single thing in it. Anything else in there was put there by something
  # else, and rmdir refusing is the correct outcome, not an error to report.
  [[ $DOT_DRY_RUN == 1 ]] || rmdir "$(dirname "$DOT_CONFIG")" 2>/dev/null || true
else
  say 'None found.'
fi

# --- Backups -----------------------------------------------------------------------
heading 'Backups'
if [[ -n $(find "$DOT_STATE/backups" -mindepth 1 -print -quit 2>/dev/null) ]]; then
  # A warning about something KEPT, which is the unusual direction for one. It
  # is here because the alternative -- a quiet `dim` line -- is how you find out
  # six months later that the only copy of a config you spent an evening on has
  # been sitting in ~/.local/state all along.
  warn "kept  ${DOT_STATE/#$HOME/\~}/backups"
  dim 'Your own files, moved aside by an earlier apply. Nothing else has a copy.'
  dim 'Delete them yourself once you have looked.'
else
  say 'None to keep.'
  # The state directory goes with them -- but only if the (now empty) backup
  # tree was the whole of it. A recursive delete here would take anything else
  # that ended up in ~/.local/state/dotfiles along with it, and an uninstall
  # removing a file nothing in this repo created is the one mistake it cannot
  # undo; there is a v1 brew-bundle.log sitting in exactly that directory on
  # the author's machine. rmdir cannot recurse and refuses a non-empty
  # directory, so the safeguard is the verb rather than the caller -- the same
  # reason the Config section above uses it.
  #
  # Tested before acting rather than left to rmdir's exit status, so that a dry
  # run and a real run print the same sentence.
  #
  # The find sits inside `[[ -n $(...) ]]` rather than in a `stray=$(...)`
  # assignment for the reason CLAUDE.md gives: find exits 1 on a directory that
  # is not there, and under `set -e` that status kills a bare assignment. A
  # test context is exempt. The -d guard is what keeps the message honest, not
  # what keeps the script alive.
  if [[ -d $DOT_STATE ]]; then
    if [[ -n $(find "$DOT_STATE" -mindepth 1 -not -path "$DOT_STATE/backups" -print -quit 2>/dev/null) ]]; then
      warn "left alone  ${DOT_STATE/#$HOME/\~} holds files this repo did not create"
    else
      info "remove  ${DOT_STATE/#$HOME/\~}"
      [[ $DOT_DRY_RUN == 1 ]] || rmdir "$DOT_STATE/backups" "$DOT_STATE" 2>/dev/null || true
    fi
  fi
fi

# --- Applications ---------------------------------------------------------------
#
# The leftover this section exists to prevent. Homebrew MOVES a cask's .app into
# /Applications, so it no longer resolves back into the Cellar -- and Homebrew's
# own uninstaller deletes the prefix and nothing outside it. Left to itself it
# would strand every GUI app on the machine: still installed, with nothing left
# that can update or remove it. `brew services` leaks the same way, its launchd
# plists living in ~/Library/LaunchAgents, equally outside the prefix.
#
# The fix is ordering, not machinery. Homebrew knows exactly what it put where,
# right up until the step that destroys that knowledge -- so spend it first.
# Everything here has to happen while brew still works.
heading 'Applications'

# Services before apps: a launchd job whose binary was torn out from under it
# is a worse state than a job stopped a second early.
if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'brew services stop --all'
else
  brew services stop --all >/dev/null 2>&1 || true
fi

mapfile -t casks < <(brew list --cask 2>/dev/null)
if ((${#casks[@]} == 0)); then
  say 'None installed.'
elif [[ $DOT_DRY_RUN == 1 ]]; then
  for cask in "${casks[@]}"; do
    info "uninstall  $cask"
  done
  dim '--zap as well: application support, preferences and caches go too'
elif brew uninstall --cask --zap --force "${casks[@]}"; then
  ok "removed ${#casks[@]} application(s)"
else
  # Ask brew what survived rather than reporting which command failed: the
  # authoritative answer to "what is still installed" is the thing that knows.
  #
  # These are `fail`, so the guard further down stops the run before the
  # handoff -- and that is the entire point of doing this while brew is alive.
  # Destroying the only tool that could remove an app you just failed to remove
  # would manufacture the exact leftover this section is here to prevent.
  while IFS= read -r cask; do
    fail "could not remove $cask -- remove it by hand, then re-run"
  done < <(brew list --cask 2>/dev/null)
fi

# brew_headcount -- print "<formulae installed> <formulae this repo never named>".
#
# This line used to read "Homebrew and every package it installed", which is
# true and which reads as "the packages this repo installed". That is the one
# misreading that matters, because the answer is every package on the machine:
# Homebrew's uninstaller removes the whole Cellar and Caskroom and keeps no
# record of who asked for what, so a formula you installed by hand three years
# ago goes with the rest. A count is harder to misread than a sentence -- the
# same lesson as doctor's Result line, which said "Everything looks right" over
# a list of orphaned links until it started reading its own tallies.
brew_headcount() {
  local installed repo bundle
  command -v brew >/dev/null 2>&1 || return 1

  installed=$(mktemp) repo=$(mktemp) bundle=$(mktemp)

  # Formulae only, on both sides -- `brew bundle list` defaults to the same.
  # The casks were itemised by name in the section above, and counting them
  # again here would have the preview claim the same applications twice.
  brew list --formula 2>/dev/null | sort -u >"$installed"
  cat "$DOT_ROOT"/core/Brewfile "$DOT_ROOT"/modules/*/Brewfile 2>/dev/null >"$bundle"
  brew bundle list --file "$bundle" 2>/dev/null | sort -u >"$repo"

  printf '%s %s\n' \
    "$(wc -l <"$installed" | tr -d ' ')" \
    "$(comm -23 "$installed" "$repo" | wc -l | tr -d ' ')"

  rm -f "$installed" "$repo" "$bundle"
}

# --- Handoff --------------------------------------------------------------------------
heading 'Homebrew and the repo'

# Stopping short of the irreversible half when the reversible half went wrong.
# Everything above is a thing `dot apply` can put back; nothing below is.
if ((DOT_FAILURES > 0)); then
  die "$DOT_FAILURES problem(s) above -- stopping before Homebrew and the repo."
fi

if [[ $DOT_DRY_RUN == 1 ]]; then
  # `read` runs in this shell; only the process substitution is a subshell, so
  # both numbers survive. See docs/bash-guide.md.
  if read -r n_all n_foreign < <(brew_headcount); then
    info "uninstall Homebrew and all $n_all formulae it manages"
    # A warning, because this is the part nobody expects: those packages are
    # not this repo's, and it is removing them anyway.
    ((n_foreign == 0)) ||
      warn "$n_foreign of those are named by no Brewfile here -- they go too"
  else
    info 'uninstall Homebrew and every package it manages'
  fi
  info "remove  $DOT_ROOT"
  heading 'Dry run'
  dim 'Nothing was changed.'
  exit 0
fi

# The last two steps remove the ground this script is standing on: Homebrew owns
# the bash 5 interpreting it, and $DOT_ROOT holds the file itself. So they do
# not run here. install.sh ends by exec'ing into the repo; this ends by exec'ing
# out of it, into a throwaway script that depends on neither -- which turns a
# question about when bash re-reads a deleted file into no question at all.
#
# /bin/bash on purpose: macOS's own 3.2, the one shell still guaranteed to be
# there once Homebrew is gone. Nothing below needs bash 5.
handoff=$(mktemp -t dotfiles-uninstall)
cat >"$handoff" <<EOF
#!/bin/bash
set -u
echo
echo "==> Uninstalling Homebrew (it will ask for your password)"
# NONINTERACTIVE=1 implies --force in Homebrew's uninstaller, so it does not
# re-ask "are you sure" -- you already typed 'remove' once, and a second
# prompt for the same decision is how people learn to answer without reading.
NONINTERACTIVE=1 /bin/bash -c "\$(curl -fsSL $BREW_UNINSTALL)"
echo
echo "==> Removing $DOT_ROOT"
rm -rf "$DOT_ROOT"
echo
echo "==> Done."
echo "    Xcode Command Line Tools were left installed, on purpose."
echo "    Open a new terminal: this one still has the old PATH."
rm -f "\$0"
EOF

exec /bin/bash "$handoff"
