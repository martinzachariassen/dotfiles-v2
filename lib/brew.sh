# shellcheck shell=bash
#
# Homebrew. Thin on purpose: `brew bundle` is already idempotent.

brew_load() {
  command -v brew >/dev/null 2>&1 && return 0
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return 0
  fi
  return 1
}

# brew_bundle FILE [LABEL] -- a missing Brewfile is success: modules need none.
brew_bundle() {
  local file=$1
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

  # --no-upgrade: apply installs what is missing; upgrading is `brew upgrade`.
  if brew bundle --file "$file" --no-upgrade; then
    return 0
  else
    fail "brew bundle failed for $label"
    return 1
  fi
}
