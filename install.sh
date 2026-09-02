#!/usr/bin/env bash
#
# Phase 0 bootstrap. This is the URL:
#
#   curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles-v2/main/install.sh | bash
#
# Everything interesting happens in `dot apply`, which this hands off to.
#

set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles-v2.git}"
REPO_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles-v2}"

echo "==> dotfiles bootstrap"
echo "    repo: $REPO_URL"
echo "    into: $REPO_DIR"
echo

# Progress is printed as "[n/5]" so an unattended run says where it is. This is
# a helper rather than the number written out at each site: the count changes
# every time a step is added, and last time it did, the copies drifted.
TOTAL_STEPS=5
step() {
  printf '==> [%s/%s] %s\n' "$1" "$TOTAL_STEPS" "$2"
}

# --- Guards -----------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || {
  echo "This is macOS only." >&2
  exit 1
}
[ "$(id -u)" -ne 0 ] || {
  echo "Do not run this as root." >&2
  exit 1
}
[ "$(uname -m)" = "arm64" ] || {
  echo "! Not Apple Silicon; exiting."
  exit 1
}

# --- 1. Xcode Command Line Tools --------------------------------------------
# Homebrew needs a compiler and git. The GUI installer runs asynchronously, so
# trigger it and wait rather than racing it.
if xcode-select -p >/dev/null 2>&1; then
  step 1 "Xcode Command Line Tools already installed"
else
  step 1 "Installing Xcode Command Line Tools (click Install in the dialog)"
  xcode-select --install >/dev/null 2>&1 || true

  attempts=0
  max_attempts=180 # 180 * 10s = 30 minutes
  until xcode-select -p >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      echo
      echo "Timed out waiting for Command Line Tools." >&2
      echo "Finish the dialog, then re-run this script." >&2
      exit 1
    fi
    printf '.'
    sleep 10
  done
  echo
fi

# --- 2. Homebrew ------------------------------------------------------------
if [ -x /opt/homebrew/bin/brew ]; then
  step 2 "Homebrew already installed"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  step 2 "Installing Homebrew (it will ask for your password)"

  # One prompt up front beats several mid-run -- but priming it once is not
  # enough. NONINTERACTIVE=1 means Homebrew's installer never stops to ask, and
  # the credential expires after five minutes, which a cold install on a slow
  # connection takes longer than: it failed after the download, with a
  # permission error, on the machines least able to afford the retry. The loop
  # refreshes it, and stops by itself the moment refreshing stops working.
  sudo -v
  while sudo -n true 2>/dev/null; do sleep 50; done &
  keepalive=$!
  # Also on the error paths: `set -e` must not leave sudo renewing itself.
  trap 'kill "$keepalive" 2>/dev/null || true' EXIT

  # /bin/bash on purpose: this is Homebrew's own installer, which supports the
  # system shell. Everything belonging to THIS repo needs bash 5 -- installed
  # in the next step.
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Before the `exec` below, which keeps the PID and does not run EXIT traps:
  # a keepalive left running here would follow `dot apply` around.
  kill "$keepalive" 2>/dev/null || true
  trap - EXIT

  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "    Homebrew at $(brew --prefix)"

# --- 3. bash 5 ---------------------------------------------------------------
# macOS ships bash 3.2 from 2007 and never updates it. Every script in this
# repo needs 5, and they start running in step 5 -- before core/Brewfile gets
# its turn -- so this one package cannot wait for the normal package phase.
if brew list --versions bash >/dev/null 2>&1; then
  step 3 "bash 5 already installed"
else
  step 3 "Installing bash 5 (macOS ships 3.2, from 2007)"
  brew install bash
fi

# --- 4. The repo ------------------------------------------------------------
if [ -d "$REPO_DIR/.git" ]; then
  step 4 "Updating existing checkout"
  git -C "$REPO_DIR" pull --ff-only
elif [ -e "$REPO_DIR" ]; then
  echo "$REPO_DIR exists and is not a git checkout. Move it aside first." >&2
  exit 1
else
  step 4 "Cloning"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth=1 "$REPO_URL" "$REPO_DIR"
fi

# --- 5. Hand off ------------------------------------------------------------
# From here the repo is on disk and `dot` owns the process.
# Phase 1 (core packages) installs `dasel` and `fzf`; phase 2 asks what you want and applies it.
step 5 "Handing off to dot apply"
echo

# Under `curl | bash` this script's stdin is the pipe, not the keyboard, so the
# wizard is handed the terminal explicitly. Checked first: without a
# controlling terminal the redirect fails with a bare "No such device or
# address", which says nothing about what to do next.
if [ ! -r /dev/tty ]; then
  echo "No terminal available, so the setup wizard cannot ask anything." >&2
  echo "Run this instead, from a terminal:" >&2
  echo "  $REPO_DIR/bin/dot apply" >&2
  exit 1
fi

exec bash "$REPO_DIR/bin/dot" apply </dev/tty
