# shellcheck shell=bash
#
# The module registry and the apply driver.
#
# THE DIRECTORY LISTING IS THE REGISTRY. Adding a module means creating a
# directory under modules/; there is no central list to update, because a
# central list is a thing that can disagree with the filesystem. What keeps
# that safe is tests/contract.bats, which walks the same glob and enforces the
# contract every module must satisfy.

[[ -n ${__DOT_MODULES_SH:-} ]] && return 0
__DOT_MODULES_SH=1

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

# --- Manifest fields (the four that exist; a fifth needs justifying) --------
module_desc() { toml_get "$(module_manifest "$1")" 'description' "$1"; }
module_order() { toml_get "$(module_manifest "$1")" 'order' '50'; }
module_default() { [[ $(toml_get "$(module_manifest "$1")" 'default' 'false') == true ]]; }
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

# modules_sort -- read names on stdin, emit them ordered by (order, name).
#
# One ordering axis, used by both apply and doctor. v1 had a separate
# FEATURE_DOCTOR_ORDER, which is a second thing to keep in sync for no gain.
modules_sort() {
  local name
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    printf '%s\t%s\n' "$(module_order "$name")" "$name"
  done | sort -k1,1n -k2,2 | cut -f2
}

# Modules the config asks for, minus any that no longer exist in the repo.
# A stale name is a warning, not a hard error: deleting a module from the repo
# should not brick every machine that still lists it.
modules_enabled() {
  local name
  while IFS= read -r name; do
    if module_exists "$name"; then
      printf '%s\n' "$name"
    else
      warn "config lists unknown module '$name' -- ignoring"
    fi
  done < <(cfg_list 'modules.enabled') | modules_sort
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

  DOT_MODULE=$name \
    DOT_MODULE_DIR="$(modules_dir "$name")" \
    bash "$script"
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
