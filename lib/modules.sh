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

# --- Manifest fields (the one that exists; a second needs justifying) -------
module_desc() { toml_get "$(module_manifest "$1")" 'description' "$1"; }

# module_setting NAME KEY [DEFAULT] -- read [settings.<name>].<key> from the
# user config.
#
# Bracket syntax is mandatory, not stylistic: dasel's selector language treats
# a dash as subtraction, so `settings.macos-defaults.dock` parses as arithmetic
# and fails with a type error. Neither "" nor '' quoting helps. Every module
# setting goes through here so no module author has to discover that.
module_setting() {
  local name=$1 key=$2 default=${3:-}
  cfg_get "settings[\"$name\"].$key" "$default"
}

module_setting_bool() {
  [[ $(module_setting "$1" "$2" "${3:-false}") == true ]]
}

# Modules the config asks for, minus any that no longer exist in the repo.
#
# Alphabetical. Modules are independent by design -- each one's apply.sh
# assumes only that core has run -- so name order is as good as any, and it
# makes two runs read identically. There was an `order` field once; every
# module set it to 50.
#
# Silent by design, and it cannot be otherwise: a single run asks more than
# once, and every caller reads it as `< <(modules_enabled)`, a subshell. A
# warning printed here appears once per caller, and no cache fixes that,
# because a variable set in a subshell never reaches the parent. Complaining
# about unknown names is modules_require_known's job, called once.
#
# `if` rather than `&&`: with pipefail, a trailing `&&` whose test fails leaves
# the loop at status 1, which propagates out through `| sort` and kills any
# caller doing `x=$(modules_enabled)` under `set -e`. One unknown name sorting
# last is enough to trigger it.
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
# precisely so you can -- so a typo is likely, and merely warning is the worst
# failure mode available: `dot apply` reports success having quietly installed
# three modules out of four. `dot doctor` reports rather than dies; it is the
# read-only verb.
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

# Every module directory in the repo, enabled or not. fs_repo_links scans
# these: a link left behind by a module you just disabled is the main thing it
# looks for, so the enabled set is the wrong input for deciding where to look.
modules_all_dirs() {
  local name
  while IFS= read -r name; do
    modules_dir "$name"
  done < <(modules_all)
}

# --- Hooks -----------------------------------------------------------------
#
# Hooks are EXECUTED in a fresh bash process, never sourced. Process isolation
# means a hook cannot leak a variable or a shell option into the driver, and it
# means `bash modules/git/doctor.sh` reproduces exactly what `dot doctor` does
# -- the difference between a debuggable hook and a mysterious one.
module_run_hook() {
  local name=$1 hook=$2 script
  script="$(modules_dir "$name")/$hook"
  [[ -f $script ]] || return 0

  # "$BASH" rather than bare `bash`: the hook runs under the same interpreter
  # as the driver, not whatever PATH happens to resolve to.
  DOT_MODULE=$name \
    DOT_MODULE_DIR="$(modules_dir "$name")" \
    "$BASH" "$script"
}

# module_apply NAME -- packages, then links, then imperative steps. The order
# is fixed so apply.sh can always assume its packages are installed and its
# config files are already in place.
module_apply() {
  local name=$1 dir packaged=1
  dir=$(modules_dir "$name")

  # A failing Brewfile stops this module, not the run. brew_bundle has already
  # called `fail`, so the tally is right either way -- but called bare, its
  # `return 1` tripped `set -e` and every module after this one was skipped.
  # One unavailable cask must not cost you the other five modules.
  brew_bundle "$dir/Brewfile" "$name" || packaged=0

  # Linked anyway: files depend on nothing but the repo. apply.sh is not, since
  # its one documented promise is that its packages are already installed.
  fs_link_tree "$dir"

  # fold_status, not `if ! module_run_hook`: that read every non-zero status as
  # a crash, so the one `warn` in git/apply.sh -- an empty user.name, which the
  # hook is written to shrug at -- was reported as "git: apply.sh failed".
  if ((packaged)); then
    fold_status "$name: apply.sh failed" module_run_hook "$name" apply.sh
  else
    dim "skipped $name/apply.sh -- its packages are not installed"
  fi
}

# module_doctor NAME -- read-only checks. Never modifies anything.
#
# Counts its own failures rather than returning a status for the caller to
# convert: bin/dot called this as `|| true`, which swallowed both a drifted
# file tree and a failing doctor.sh, so `dot doctor` printed "Everything looks
# right" over a module that was not linked at all.
module_doctor() {
  local name=$1 dir tracked=''
  dir=$(modules_dir "$name")

  # Does this module track any files at all? Asked because a heading with
  # nothing under it reads as a check that died quietly, and silence was the
  # whole report for two shapes of module: one that is only a Brewfile, and one
  # whose files are all correctly linked (fs_check_tree prints drift only).
  if [[ -d $dir/home ]]; then
    tracked=$(find "$dir/home" -type f -print -quit)
  fi

  if [[ -z $tracked && ! -f $dir/doctor.sh ]]; then
    dim 'packages only -- nothing to check'
    return 0
  fi

  # One summary line per module, not one per file: fs_check_tree named each
  # path already.
  if fs_check_tree "$dir"; then
    if [[ -n $tracked ]]; then ok 'files        all linked'; fi
  else
    fail "$name: files are not linked -- run: dot apply"
  fi

  fold_status "$name: doctor.sh reported problems" module_run_hook "$name" doctor.sh
}

# module_remove NAME -- the module's own cleanup, for uninstall.sh.
#
# The third hook, and it earns its place on one specific gap rather than on
# symmetry. The generic sweep removes symlinks pointing INTO the repo, which is
# most of what a module leaves behind but not all: containers links Homebrew's
# docker plugins, whose targets live under brew's prefix, and git writes a real
# file. Neither is visible to a scan filtered on $DOT_ROOT -- and widening that
# filter would mean deleting links this repo never made.
#
# Called for EVERY module in the repo, not the enabled ones: a module switched
# off last month still left its files behind, and an uninstall is the one run
# that is supposed to find them.
module_remove() {
  fold_status "$1: remove.sh failed" module_run_hook "$1" remove.sh
}
