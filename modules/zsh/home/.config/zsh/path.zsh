# PATH. Sourced first by .zshrc, so everything after it can find these.

# Homebrew. Apple Silicon first, Intel second.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Where `dot` lives. This is the line core/doctor.sh checks for.
path=("$HOME/.local/bin" $path)

# typeset -U keeps PATH free of duplicates when a shell is re-sourced.
typeset -U path PATH
export PATH
