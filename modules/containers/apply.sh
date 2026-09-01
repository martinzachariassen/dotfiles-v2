#!/usr/bin/env bash
#
# Make Homebrew's compose and buildx visible to the docker CLI.
#
# Homebrew installs them as plugin binaries under its own prefix, and the
# docker CLI only looks in ~/.docker/cli-plugins. Without these links
# `docker compose up` is an unknown command while `docker-compose up` works --
# the kind of split that costs twenty minutes the first time.
#
# Homebrew's caveat suggests `cliPluginsExtraDirs` in ~/.docker/config.json
# instead. That is the same file `docker login` writes credentials into, so
# this module links rather than edit it.
#
# The links are made with fs_link, the same function that links every module's
# home/ tree: it is idempotent, it honours --dry-run, and a real file in the
# way is moved to the backup tree rather than destroyed. The only difference
# is that the source is in Homebrew's prefix instead of this repo.

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
