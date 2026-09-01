# shellcheck shell=bash
#
# The module registry and the apply driver.
#
# THE DIRECTORY LISTING IS THE REGISTRY. Adding a module means creating a
# directory under modules/; there is no central list to update, because a
# central list is a thing that can disagree with the filesystem. What keeps
# that safe is tests/contract.bats, which walks the same glob and enforces the
# contract every module must satisfy.

modules_dir() { printf '%s\n' "$DOT_ROOT/modules/$1"; }
module_manifest() { printf '%s\n' "$(modules_dir "$1")/module.toml"; }

# Every module present in the repo, alphabetically.
modules_all() {
  local dir
  for dir in "$DOT_ROOT"/modules/*/; do
    [[ -f "$dir/module.toml" ]] || continue
    basename "$dir"
  done
}

module_exists() { [[ -f $(module_manifest "$1") ]]; }

# --- Manifest fields (the two that exist; a third needs justifying) ---------
module_desc() { toml_get "$(module_manifest "$1")" 'description' "$1"; }
module_sudo() { [[ $(toml_get "$(module_manifest "$1")" 'sudo' 'false') == true ]]; }

# module_setting NAME KEY [DEFAULT] -- read [settings.<name>].<key> from the
# user config.
#
# Bracket syntax is mandatory here, not stylistic. dasel's selector language
# treats a dash as subtraction, so `settings.macos-defaults.dock` parses as an
# arithmetic expression and fails with a type error. Quoting with "" or ''
# does not help; only settings["macos-defaults"] works. Every module setting
# goes through this function so no module author ever has to discover that.
module_setting() {
  local name=$1 key=$2 default=${3:-}
  cfg_get "settings[\"$name\"].$key" "$default"
}

module_setting_bool() {
  [[ $(module_setting "$1" "$2" "${3:-false}") == true ]]
}

# Modules the config asks for, minus any that no longer exist in the repo.
#
# Alphabetical, via the trailing `| sort`. Modules are independent by design --
# each one's apply.sh assumes only that core has run -- so name order is as
# good as any, and it makes two runs read identically. There was an `order`
# field once; every module set it to 50.
#
# Silent by design, and it cannot be otherwise. A single run asks several times
# -- the sudo check, the apply loop, the orphan scan -- and every caller reads
# it as `< <(modules_enabled)`, which is a subshell (see docs/bash-guide.md).
# So a warning printed in here appears once per caller, and no amount of
# caching fixes that: a variable set inside a subshell never reaches the
# parent. Complaining about unknown names is modules_require_known's job,
# called once, from the one place that knows a run has started.
#
# `if` rather than `&&`: with pipefail, a trailing `&&` whose test fails leaves
# the loop at status 1, which propagates out of the pipeline and kills any
# caller doing `x=$(modules_enabled)` under `set -e`. It only takes one unknown
# name sorting last to trigger it.
modules_enabled() {
  local name
  while IFS= read -r name; do
    if module_exists "$name"; then printf '%s\n' "$name"; fi
  done < <(cfg_list 'modules.enabled') | sort
}

# Names the config lists that the repo has no module for -- typos, or modules
# deleted from the repo since the config was written.
modules_unknown() {
  local name
  while IFS= read -r name; do
    if ! module_exists "$name"; then printf '%s\n' "$name"; fi
  done < <(cfg_list 'modules.enabled')
}

# Refuse to apply a config that names something that does not exist.
#
# Hand-editing config.toml is a supported workflow -- the `none` profile exists
# precisely so you can -- so a typo there is likely, and the failure mode of
# merely warning is the worst one available: `dot apply` reports success having
# quietly installed three modules out of four. Stopping costs one edit.
# `dot doctor` still reports rather than dies; it is the read-only verb.
modules_require_known() {
  local unknown available
  unknown=$(modules_unknown | tr '\n' ' ')
  [[ -z ${unknown// /} ]] && return 0
  available=$(modules_all | tr '\n' ' ')
  die "config lists module(s) that do not exist: ${unknown% }
    available:  ${available% }
    edit:       $DOT_CONFIG"
}

modules_enabled_dirs() {
  local name
  while IFS= read -r name; do
    modules_dir "$name"
  done < <(modules_enabled)
}

# --- Hooks -----------------------------------------------------------------
#
# apply.sh and doctor.sh are EXECUTED in a fresh bash process, never sourced.
# Process isolation means a hook cannot leak a variable or a shell option into
# the driver, and it means `bash modules/git/doctor.sh` reproduces exactly what
# `dot doctor` does -- which is the difference between a debuggable hook and a
# mysterious one.
module_run_hook() {
  local name=$1 hook=$2 script
  script="$(modules_dir "$name")/$hook"
  [[ -f $script ]] || return 0

  # "$BASH" rather than bare `bash`: the hook then runs under the same
  # interpreter as the driver, not whatever PATH happens to resolve to.
  DOT_MODULE=$name \
    DOT_MODULE_DIR="$(modules_dir "$name")" \
    "$BASH" "$script"
}

# module_apply NAME -- packages, then links, then imperative steps.
#
# The order is fixed so apply.sh can always assume its packages are installed
# and its config files are already in place.
module_apply() {
  local name=$1 dir
  dir=$(modules_dir "$name")

  brew_bundle "$dir/Brewfile" "$name"
  fs_link_tree "$dir"

  if ! module_run_hook "$name" apply.sh; then
    fail "$name: apply.sh failed"
  fi
}

# module_doctor NAME -- read-only checks. Never modifies anything.
module_doctor() {
  local name=$1 dir failed=0
  dir=$(modules_dir "$name")

  fs_check_tree "$dir" || failed=1
  module_run_hook "$name" doctor.sh || failed=1
  return $failed
}

# True if any enabled module declares sudo = true, so the driver can prime the
# credential once up front instead of letting prompts interrupt a long run.
modules_want_sudo() {
  local name
  while IFS= read -r name; do
    module_sudo "$name" && return 0
  done < <(modules_enabled)
  return 1
}
