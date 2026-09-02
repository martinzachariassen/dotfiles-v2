#!/usr/bin/env bash
#
# Nothing starts colima for you. A stopped VM makes every docker command fail
# with a connection error that names a socket rather than the reason.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if ! command -v colima >/dev/null 2>&1; then
  fail 'colima       not installed (run: dot apply)'
elif [[ ! -d $HOME/.colima/default ]]; then
  # `colima status` is NOT read-only: on a machine that never started the VM it
  # creates ~/.colima/_lima before answering. doctor promises to change nothing,
  # so it only asks once there is state to ask about. (remove.sh has the same
  # landmine and MUST TEST THE SAME PATH -- it decides there whether to stop a
  # VM and whether to warn that one is still on disk.)
  #
  # The profile directory, not ~/.colima: this module links a file into
  # ~/.colima/_templates, so the parent exists from `dot apply` onward on a
  # machine that has never run colima. `colima start` is what creates
  # ~/.colima/default, which is the question actually being asked.
  warn 'colima       no VM yet (create and start one with: colima start)'
elif colima status >/dev/null 2>&1; then
  ok 'colima       running'
else
  warn 'colima       not running (start it with: colima start)'
fi

# `sshConfig: true` is colima's default, and it means every `colima start`
# prepends an Include line to ~/.ssh/config. That path is a symlink into this
# repo, so the write lands in modules/ssh/home/.ssh/config -- tracked, with an
# absolute /Users/<you>/ path in it, above the config.local Include that file
# documents as having to come first (ssh takes the first value it obtains).
#
# Checked here because nothing else can see it. fs_check_tree classifies the
# link, not its contents, and the link is still correct -- so doctor calls the
# ssh module healthy while the repo carries another machine's paths. Reading
# the file creates nothing, unlike `colima status` above.
colima_yaml="$HOME/.colima/default/colima.yaml"
if [[ -f $colima_yaml ]] && grep -qE '^[[:space:]]*sshConfig:[[:space:]]*true' "$colima_yaml"; then
  warn 'colima       sshConfig is on -- `colima start` edits ~/.ssh/config, which is a link into this repo'
  dim '             turn it off: colima stop && colima start --ssh-config=false'
fi
