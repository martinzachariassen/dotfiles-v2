# shellcheck shell=bash
#
# First-run config generation. Runs exactly once per machine, after phase 1 has
# installed fzf -- which is the whole reason this file is short. v1's wizard
# ran under `curl | bash` before any tool existed and grew to 587 lines of
# hand-rolled pickers.
#
# HARD CAP: 60 lines of code. If this needs a loop over a question schema,
# stop and reconsider -- that is how the last one started.

[[ -n ${__DOT_WIZARD_SH:-} ]] && return 0
__DOT_WIZARD_SH=1

DOT_PROFILES="$DOT_ROOT/profiles.toml"

# Profiles are wizard presets and nothing more. They seed the checklist below;
# what lands in config.toml is always the explicit module list. `dot apply`
# does not know profiles exist, so there is no inheritance to reason about.
wizard_pick_profile() {
  local names
  names=$(toml_list "$DOT_PROFILES" 'profiles.keys()')
  [[ -z $names ]] && return 0
  printf '%s\ncustom\n' "$names" |
    fzf --height=40% --reverse --prompt='Profile > ' \
      --header='Starting point for the module list (Enter to choose)'
}

# fzf --multi cannot pre-tick rows, so the checkmark is advisory and the
# selection replaces the list wholesale. The alternative -- a --bind toggle
# loop holding its own state -- is exactly the road to a 587-line wizard.
wizard_pick_modules() {
  local preset=$1 name mark
  while IFS= read -r name; do
    if printf '%s\n' "$preset" | grep -qx "$name"; then mark='*'; else mark=' '; fi
    printf '%s %-20s %s\n' "$mark" "$name" "$(module_desc "$name")"
  done < <(modules_all) |
    fzf --multi --height=60% --reverse --prompt='Modules > ' \
      --header='TAB to toggle, Enter to confirm. * = in the chosen profile.' |
    awk '{print $2}'
}

wizard_run() {
  local profile preset modules name email

  heading 'Choose what to install'
  profile=$(wizard_pick_profile)
  if [[ -n $profile && $profile != custom ]]; then
    preset=$(toml_list "$DOT_PROFILES" "profiles.$profile")
  else
    # No profile chosen: start from whatever declares itself a sane default.
    preset=$(while IFS= read -r name; do
      module_default "$name" && printf '%s\n' "$name"
    done < <(modules_all))
  fi

  modules=$(wizard_pick_modules "$preset")
  [[ -z $modules ]] && modules=$preset

  heading 'Git identity'
  local default_name default_email
  default_name=$(git config --global user.name || true)
  default_email=$(git config --global user.email || true)
  read -r -p "  Full name  [$default_name]: " name
  read -r -p "  Email      [$default_email]: " email
  name=${name:-$default_name}
  email=${email:-$default_email}

  config_generate "$name" "$email" "$modules"
}
