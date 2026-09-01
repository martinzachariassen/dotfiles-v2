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
echo "==> [1/4] Installing Xcode Command Line Tools (it will ask for your password)"
attempts=0
max_attempts=180  # 180 * 10s = 30 minutes
until xcode-select -p >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge "$max_attempts" ]; then
    echo
    echo "==> [1/4] Timed out waiting for Command Line Tools. Finish the dialog and re-run this script." >&2
    exit 1
  fi
  printf '.'
  sleep 10
done
echo

# --- 2. Homebrew ------------------------------------------------------------
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "==> [2/4] Installing Homebrew (it will ask for your password)"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo "==> [2/4] Homebrew at $(brew --prefix)"

# --- 3. The repo ------------------------------------------------------------
if [ -d "$REPO_DIR/.git" ]; then
  echo "==> [3/4] Updating existing checkout"
  git -C "$REPO_DIR" pull --ff-only
elif [ -e "$REPO_DIR" ]; then
  echo "==> [3/4] $REPO_DIR exists and is not a git checkout. Move it aside first." >&2
  exit 1
else
  echo "==> [3/4] Cloning"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth=1 "$REPO_URL" "$REPO_DIR"
fi

# --- 4. Hand off ------------------------------------------------------------
# From here the repo is on disk and `dot` owns the process.
# Phase 1 (core packages) installs `dasel` and `fzf`; phase 2 asks what you want and applies it.
echo "==> [4/4] Handing off to dot apply"
echo
exec bash "$REPO_DIR/bin/dot" apply
