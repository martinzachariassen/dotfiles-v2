#!/usr/bin/env bash
#
# Make Homebrew's compose and buildx visible to the docker CLI.
#
# Homebrew installs them under its own prefix; the docker CLI only looks in
# ~/.docker/cli-plugins. Without these links `docker compose up` is an unknown
# command while `docker-compose up` works -- a split that costs twenty minutes
# the first time.
#
# Homebrew's caveat suggests `cliPluginsExtraDirs` in ~/.docker/config.json
# instead. That is the file `docker login` writes credentials into, so this
# module links rather than edit it.
#
# fs_link, so these behave like every other link: idempotent, --dry-run aware,
# and a real file in the way is backed up rather than destroyed. Their targets
# are outside $DOT_ROOT, though, which is why remove.sh has to name them.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

brew_load || die 'Homebrew is not on PATH; cannot find the docker plugins'

plugin_dir="$(brew --prefix)/lib/docker/cli-plugins"

for plugin in docker-compose docker-buildx; do
  if [[ -x "$plugin_dir/$plugin" ]]; then
    fs_link "$plugin_dir/$plugin" "$HOME/.docker/cli-plugins/$plugin"
  else
    warn "$plugin is not installed -- brew bundle should have. Run: dot apply"
  fi
done
