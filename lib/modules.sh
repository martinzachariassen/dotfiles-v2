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

# Every module directory in the repo, enabled or not. fs_orphans scans these:
# a link left behind by a module you just disabled is the main thing it looks
# for, so the enabled set is the wrong input for deciding where to look.
modules_all_dirs() {
  local name
  while IFS= read -r name; do
    modules_dir "$name"
  done < <(modules_all)
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

  # Not `if ! module_run_hook`: that read every non-zero status as a crash, so
  # the one `warn` in git/apply.sh -- an empty user.name, which the hook is
  # written to shrug at -- was reported as "git: apply.sh failed".
  fold_status "$name: apply.sh failed" module_run_hook "$name" apply.sh
}

# module_doctor NAME -- read-only checks. Never modifies anything.
#
# Counts its own failures rather than returning a status for the caller to
# convert: bin/dot called this as `|| true`, which swallowed both a drifted
# file tree and a failing doctor.sh, so `dot doctor` printed "Everything looks
# right" over a module that was not linked at all. `fail` is the right verb
# here for the same reason core uses it -- this is what stops the next apply.
#
# One summary line per module, not one per file: fs_check_tree already named
# each path.
module_doctor() {
  local name=$1 dir
  dir=$(modules_dir "$name")

  fs_check_tree "$dir" || fail "$name: files are not linked -- run: dot apply"
  fold_status "$name: doctor.sh reported problems" module_run_hook "$name" doctor.sh
}

# module_remove NAME -- the module's own cleanup, for uninstall.sh.
#
# The third hook, and it earns its place on one specific gap rather than on
# symmetry. The generic sweep removes symlinks that point INTO the repo, which
# is most of what a module leaves behind but not all of it: the containers
# module links Homebrew's docker plugins, whose targets live under brew's
# prefix, and the git module writes a real file. Neither is visible to a scan
# that filters on $DOT_ROOT -- and widening that filter would mean deleting
# links this repo never made.
#
# Called for EVERY module in the repo, not the enabled ones. A module switched
# off last month still left its files behind, and an uninstall is the one run
# that is supposed to find them. It is optional like the other two: no
# remove.sh means the sweep was enough.
module_remove() {
  fold_status "$1: remove.sh failed" module_run_hook "$1" remove.sh
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
