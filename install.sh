#!/usr/bin/env bash
#
# Phase 0 bootstrap. This is the URL:
#
#   curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles-v2/main/install.sh | bash
#
# It runs before the repo exists, so it can depend on nothing in it. That is
# why there is no colour, no progress bar, no shared helper -- plain echo,
# start to finish.
#
# This constraint is the whole point. v1 duplicated ~100 lines of UI code into
# its bootstrap for exactly this reason, and the two copies drifted. The fix
# is not a cleverer way to share the UI: it is to have no UI worth sharing.
#
# Everything interesting happens in `dot apply`, which this hands off to.

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
[ "$(uname -m)" = "arm64" ] || echo "!   Not Apple Silicon; continuing anyway."

# --- 1. Xcode Command Line Tools --------------------------------------------
# Homebrew needs a compiler and git. The GUI installer runs asynchronously, so
# trigger it and wait rather than racing it.
if xcode-select -p >/dev/null 2>&1; then
  echo "==> [1/4] Command Line Tools already installed"
else
  echo "==> [1/4] Installing Command Line Tools (a dialog will appear)"
  xcode-select --install >/dev/null 2>&1 || true
  until xcode-select -p >/dev/null 2>&1; do
    printf '.'
    sleep 10
  done
  echo
fi

# --- 2. Homebrew ------------------------------------------------------------
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
else
  echo "==> [2/4] Installing Homebrew (it will ask for your password)"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
echo "==> [2/4] Homebrew at $(brew --prefix)"

# --- 3. The repo ------------------------------------------------------------
if [ -d "$REPO_DIR/.git" ]; then
  echo "==> [3/4] Updating existing checkout"
  git -C "$REPO_DIR" pull --ff-only
elif [ -e "$REPO_DIR" ]; then
  echo "$REPO_DIR exists and is not a git checkout. Move it aside first." >&2
  exit 1
else
  echo "==> [3/4] Cloning"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth=1 "$REPO_URL" "$REPO_DIR"
fi

# --- 4. Hand off ------------------------------------------------------------
# From here the repo is on disk and `dot` owns the process. Phase 1 (core
# packages) installs dasel and fzf; phase 2 asks what you want and applies it.
echo "==> [4/4] Handing off to dot apply"
echo
exec bash "$REPO_DIR/bin/dot" apply
