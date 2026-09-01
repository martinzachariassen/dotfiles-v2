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

# Esc and Ctrl-C make fzf exit 130 with no output, and inside `var=$(...)` that
# status is fatal under `set -e`. Every picker therefore ends in `|| true` and
# signals cancellation by printing nothing: `--multi` returns the highlighted
# row on Enter, so an empty result can only mean the user backed out.
__wizard_cancel() {
  say 'Cancelled -- no config was written.'
  exit 0
}

# The module name travels as a hidden first field, not as a position in the
# rendered text. It used to be recovered with `awk '{print $2}'`, which skips
# leading whitespace -- so every row whose marker was a space yielded the first
# word of the DESCRIPTION instead, and picking `dev-cli` wrote a module named
# "Extra" into the config. `--with-nth=2` renders only the pretty column while
# the full line, name included, still comes back on stdout.
wizard_pick_modules() {
  local preset=$1 name mark
  while IFS= read -r name; do
    mark=' '
    grep -qxF -- "$name" <<<"$preset" && mark='*'
    printf '%s\t%s %-20s %s\n' "$name" "$mark" "$name" "$(module_desc "$name")"
  done < <(modules_all) |
    fzf --multi --height=60% --reverse --prompt='Modules > ' \
      --delimiter=$'\t' --with-nth=2 \
      --header='TAB to toggle, Enter to confirm, Esc to abort. * = in the profile.' |
    cut -f1 || true
}

wizard_run() {
  local profiles profile modules name email reply

  # `none` writes an empty module list and skips the picker entirely: the
  # config file becomes the interface, and `dot apply` validates what you put
  # in it. There is deliberately no "custom" profile -- that was a second way
  # to hand-assemble a list, and the config file is already the first.
  heading 'Choose what to install'
  profiles=$(printf '%s\nnone\n' "$(toml_list "$DOT_PROFILES" 'profiles.keys()')")
  profile=$(printf '%s\n' "$profiles" | grep -v '^$' |
    fzf --height=40% --reverse --prompt='Profile > ' \
      --header='Module list to start from. none = choose them yourself, in the config. Esc to abort.' || true)
  [[ -z $profile ]] && __wizard_cancel

  if [[ $profile == none ]]; then
    modules=''
  else
    modules=$(wizard_pick_modules "$(toml_list "$DOT_PROFILES" "profiles.$profile")")
    [[ -z $modules ]] && __wizard_cancel
  fi

  heading 'Git identity'
  name=$(git config --global user.name || true)
  email=$(git config --global user.email || true)
  read -r -p "  Full name  [$name]: " reply && name=${reply:-$name}
  read -r -p "  Email      [$email]: " reply && email=${reply:-$email}

  # The config is written once and never rewritten, so a mis-pick survives
  # until you delete the file by hand. One look before that earns its lines.
  heading 'Review'
  if [[ -n $modules ]]; then
    say "modules   $(tr '\n' ' ' <<<"$modules")"
  else
    say 'modules   (none -- you add them to the config yourself)'
  fi
  say "identity  ${name:-(unset)} <${email:-(unset)}>"
  read -r -p '  Write this config? [Y/n]: ' reply
  [[ ${reply:-y} == [Yy]* ]] || __wizard_cancel

  config_generate "$name" "$email" "$modules"
  [[ -n $modules ]] || dim "Add modules to $DOT_CONFIG, then run: dot apply"
}
