#!/usr/bin/env bash
#
# The two ways a Ghostty config goes wrong without saying so.
#
# Ghostty reads FOUR paths, and the last one to mention a key wins:
#
#   1. $XDG_CONFIG_HOME/ghostty/config.ghostty                     <- this repo
#   2. $XDG_CONFIG_HOME/ghostty/config
#   3. ~/Library/Application Support/com.mitchellh.ghostty/config.ghostty
#   4. ~/Library/Application Support/com.mitchellh.ghostty/config
#
# So anything in 2-4 quietly outranks the file this module links, and when two
# of them disagree Ghostty's own error omits the filename. Nothing generic can
# catch it: fs_check_tree and the orphan scan both only look at paths a module
# claims, and this module claims exactly one of the four.
#
# The second check is the config itself. An unknown key is not a crash -- it is
# a "Configuration Errors" dialog whose detail macOS has redacted to <private>,
# so you learn the count and never the name. `+validate-config` is the only
# place those diagnostics are legible.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

ghostty_dir="$DOT_CONFIG_HOME/ghostty"
app_support="$HOME/Library/Application Support/com.mitchellh.ghostty"

# --- Anything that loads after ours ------------------------------------------
#
# Listed in load order, so the LAST one warned about is the one actually in
# charge. `if` rather than a trailing `&&`: a false test on the final iteration
# leaves the loop at status 1, which set -e turns into a dead script.
outranking=()
for f in "$ghostty_dir/config" \
  "$app_support/config.ghostty" \
  "$app_support/config"; do
  if [[ -e $f ]]; then outranking+=("${f/#$HOME/\~}"); fi
done

if ((${#outranking[@]} > 0)); then
  for f in "${outranking[@]}"; do
    warn "ghostty      $f is read after this repo's config and overrides it"
  done
  dim "             fold what you want into ~/.config/ghostty/config.ghostty, then delete the file"
else
  ok 'ghostty      nothing outranks this repo'
fi

# --- The config Ghostty actually assembles ------------------------------------
#
# No --config-file: validating the MERGED result is the point, so a bad value
# in one of the files above is caught too. The cask ships no `binary` stanza,
# so there is no `ghostty` on PATH and the absolute path is the only way in.
cli='/Applications/Ghostty.app/Contents/MacOS/ghostty'

if [[ ! -x $cli ]]; then
  # Not a failure. The module can be enabled on a machine where brew bundle has
  # not run yet, and CI never installs a cask at all.
  warn 'ghostty      not installed, config left unvalidated (run: dot apply)'
elif diagnostics=$("$cli" +validate-config 2>&1); then
  ok 'ghostty      config validates'
else
  fail 'ghostty      config has errors Ghostty will only report as a count'
  # Diagnostics come back on stdout, not stderr, which is why 2>&1 above is for
  # the stray crash rather than for these.
  while IFS= read -r line; do
    if [[ -n $line ]]; then dim "             $line"; fi
  done <<<"$diagnostics"
fi
