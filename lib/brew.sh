# shellcheck shell=bash
#
# Homebrew. Thin on purpose: `brew bundle` already knows how to be idempotent,
# so wrapping it in progress tracking or package diffing would only reimplement
# something that works.

# Put brew on PATH if it is installed but the current shell has not been told.
brew_load() {
  command -v brew >/dev/null 2>&1 && return 0
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return 0
  fi
  return 1
}

# brew_bundle FILE [LABEL] -- install everything in a Brewfile.
#
# Missing file is success, not failure: a Brewfile is optional for a module,
# and "this module has no packages" is a normal thing to be.
brew_bundle() {
  local file=$1
  # Separate statement on purpose: within a single `local`, $file is not yet
  # assigned when the default for $label is expanded (shellcheck SC2318).
  local label=${2:-$(basename "$(dirname "$file")")}
  [[ -f $file ]] || return 0

  if ! brew_load; then
    fail "Homebrew is not installed; cannot install packages for $label"
    return 1
  fi

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info "brew bundle --file ${file#"$DOT_ROOT"/}"
    return 0
  fi

  # --no-upgrade keeps apply fast and predictable: it installs what is missing
  # and leaves already-installed packages at whatever version you have.
  # Upgrading is `brew upgrade`, a thing you should choose to do.
  if brew bundle --file "$file" --no-upgrade; then
    return 0
  else
    fail "brew bundle failed for $label"
    return 1
  fi
}
