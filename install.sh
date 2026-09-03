#!/usr/bin/env bash
#
# Phase 0 bootstrap. Runs before the repo exists, so: plain echo, no library.
#
#   curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles-v2/main/install.sh | bash

set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles-v2.git}"
REPO_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles-v2}"

echo "==> dotfiles bootstrap"
echo "    repo: $REPO_URL"
echo "    into: $REPO_DIR"
echo "    plan: 1 Xcode tools  2 Homebrew  3 bash 5  4 clone  5 dot apply"
echo

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
  echo "This is Apple Silicon only; this Mac reports $(uname -m)." >&2
  exit 1
}

# --- 1. Xcode Command Line Tools --------------------------------------------
# The GUI installer is asynchronous: trigger it, then poll.
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

  # sudo's credential expires after five minutes; a cold install on a slow
  # connection takes longer, so keep it refreshed until it stops working.
  sudo -v
  while sudo -n true 2>/dev/null; do sleep 50; done &
  keepalive=$!
  trap 'kill "$keepalive" 2>/dev/null || true' EXIT

  # /bin/bash: Homebrew's installer supports the system shell. Bash 5 comes next.
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Before the `exec` below, which runs no EXIT trap.
  kill "$keepalive" 2>/dev/null || true
  trap - EXIT

  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "    Homebrew at $(brew --prefix)"

# --- 3. bash 5 ---------------------------------------------------------------
# One of four places that must agree on bash 5 (core/Brewfile, bin/dot,
# lib/dot.sh). Installed here because step 5 needs it before core/Brewfile runs.
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
step 5 "Handing off to dot apply"
echo "    It installs the core packages, asks what you want on this machine,"
echo "    then links your files. It writes a log and tells you where."
echo

# Under `curl | bash` stdin is the pipe, so the wizard is handed the terminal.
if [ ! -r /dev/tty ]; then
  echo "No terminal available, so the setup wizard cannot ask anything." >&2
  echo "Run this instead, from a terminal:" >&2
  echo "  $REPO_DIR/bin/dot apply" >&2
  exit 1
fi

exec bash "$REPO_DIR/bin/dot" apply </dev/tty
