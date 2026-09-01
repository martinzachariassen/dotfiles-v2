# Interactive shell configuration.
#
# Load order matters here:
#   1. path.zsh      so everything below can find binaries
#   2. aliases.zsh
#   3. local.zsh     machine-local, untracked, may override the above
#   4. syntax highlighting -- must be last, it wraps the line editor

# --- History ----------------------------------------------------------------
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=50000
SAVEHIST=50000
mkdir -p "${HISTFILE:h}"

setopt SHARE_HISTORY          # one history across concurrent shells
setopt HIST_IGNORE_ALL_DUPS   # keep only the most recent copy of a command
setopt HIST_IGNORE_SPACE      # a leading space keeps it out of history
setopt HIST_VERIFY            # expand !! rather than running it blind
setopt EXTENDED_HISTORY       # record timestamps

# --- Navigation -------------------------------------------------------------
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS

# --- Completion -------------------------------------------------------------
# -C reuses the cached dump when it is current; the full security check on
# every startup is the usual reason a shell feels slow to open.
autoload -Uz compinit
compinit -C -d "${XDG_STATE_HOME:-$HOME/.local/state}/zsh/zcompdump"

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors ''

# --- Key bindings -----------------------------------------------------------
bindkey -e                                  # emacs keys
bindkey '^[[A' history-search-backward      # Up: search on what you typed
bindkey '^[[B' history-search-forward

# --- This repo's parts ------------------------------------------------------
source "$ZDOTDIR/path.zsh"
source "$ZDOTDIR/aliases.zsh"

# --- Tools ------------------------------------------------------------------
command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh)"
command -v mise     >/dev/null && eval "$(mise activate zsh)"

if [[ -r $(brew --prefix 2>/dev/null)/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# --- Machine-local ----------------------------------------------------------
# Untracked, optional, and loaded late so it can override anything above.
# This is the escape hatch that keeps machine-specific settings out of git.
[[ -r "$ZDOTDIR/local.zsh" ]] && source "$ZDOTDIR/local.zsh"

# --- Must be last -----------------------------------------------------------
if [[ -r $(brew --prefix 2>/dev/null)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
