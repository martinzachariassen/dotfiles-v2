# shellcheck shell=bash
#
# Reading ~/.config/dotfiles/config.toml.
#
# There is deliberately no writer here. The config file is generated exactly
# once, by `dot config --init`, and belongs to the user from that moment on.
# Every tool that can write TOML (dasel included) rebuilds the file from its
# parsed form and drops comments in the process, so the only way to keep a
# commented, hand-editable config honest is to never write it again.
#
# Changing which modules are enabled means editing the array. That is what
# `dot config` opens your editor for.
#
# dasel v3 notes, verified against 3.11.2:
#   * there is no -f flag any more; input arrives on stdin
#   * -i is the INPUT format, not in-place editing (which v3 removed)
#   * a missing key is an error with exit status 1, which is how defaults work
#   * -o yaml is used for everything here: it renders an array as one "- item"
#     per line, and a scalar as itself. One output format means one set of
#     quoting rules to undo, in __cfg_unquote below.

cfg_exists() { [[ -f $DOT_CONFIG ]]; }

# Undo the quoting dasel's YAML output adds.
#
# YAML quotes a value only when leaving it bare would be ambiguous, so almost
# everything arrives untouched and falls straight through:
#
#   Git configuration -> Git configuration     (bare)
#   'x: y'            -> x: y                  (a colon would start a mapping)
#   ""                -> (empty string)
#   true, 3           -> true, 3               (bare)
__cfg_unquote() {
  local v=$1
  case $v in
    "'"*"'")
      v=${v:1:${#v}-2}
      # Inside single quotes YAML escapes a quote by doubling it.
      v=${v//\'\'/\'}
      ;;
    '"'*'"')
      v=${v:1:${#v}-2}
      v=${v//\\\"/\"}
      v=${v//\\\\/\\}
      ;;
  esac
  printf '%s\n' "$v"
}

# toml_get FILE KEY [DEFAULT] -- read a scalar from any TOML file.
# Used for both the user config and each module.toml, so there is one reader.
toml_get() {
  local file=$1 key=$2 default=${3:-} raw
  [[ -f $file ]] || {
    printf '%s\n' "$default"
    return 0
  }
  if raw=$(dasel -i toml -o yaml "$key" <"$file" 2>/dev/null); then
    __cfg_unquote "$raw"
  else
    printf '%s\n' "$default"
  fi
}

# toml_list FILE KEY -- read an array, one element per line.
toml_list() {
  local file=$1 key=$2 line
  [[ -f $file ]] || return 0
  dasel -i toml -o yaml "$key" <"$file" 2>/dev/null | while IFS= read -r line; do
    # An empty array renders as the single line "[]".
    [[ $line == '[]' ]] && continue
    # "- name" is one array element; strip the marker, then the same quoting
    # rules apply as for a scalar.
    line=$(__cfg_unquote "${line#- }")
    # `if`, not `&&`: a trailing `&&` that tests false on the LAST line leaves
    # the loop -- and so the pipeline -- at status 1. See docs/bash-guide.md.
    if [[ -n $line ]]; then printf '%s\n' "$line"; fi
  done
}

# --- The user config, read through the generic reader above ----------------

cfg_get() { toml_get "$DOT_CONFIG" "$1" "${2:-}"; }
cfg_list() { toml_list "$DOT_CONFIG" "$1"; }

# --- The one writer --------------------------------------------------------
#
# config_generate NAME EMAIL MODULES -- create config.toml.
#
# This is the only function in the repo that writes the config, and it runs
# once, at `dot config --init`. Afterwards the file is yours: `dot config`
# opens it in $EDITOR and nothing here ever rewrites it. That is what lets the
# comments below survive, and it is why enabling a module later is an edit
# rather than a wizard re-run.
#
# Refuses to clobber an existing file. Deleting it is an explicit act.
config_generate() {
  local name=$1 email=$2 modules=$3 line

  if cfg_exists; then
    fail "$DOT_CONFIG already exists -- delete it first to regenerate"
    return 1
  fi

  if [[ $DOT_DRY_RUN == 1 ]]; then
    info "write   $DOT_CONFIG"
    return 0
  fi

  mkdir -p "$(dirname "$DOT_CONFIG")"
  {
    cat <<'HEADER'
# dotfiles configuration.
#
# Generated once by `dot config --init`. From here on this file is yours --
# edit it freely, comments and all. Nothing in the tool rewrites it.
#
# Apply changes with:  dot apply
# Check the machine:   dot doctor

schema = 1

HEADER

    printf '[user]\nname  = "%s"\nemail = "%s"\n\n' "$name" "$email"

    printf '[modules]\n'
    printf '# Add or remove names, then run `dot apply`.\n'
    printf '# Available: %s\n' "$(modules_all | tr '\n' ' ' | sed 's/ $//')"
    printf 'enabled = [\n'
    while IFS= read -r line; do
      [[ -n $line ]] && printf '  "%s",\n' "$line"
    done <<<"$modules"
    printf ']\n\n'

    cat <<'FOOTER'
# Per-module settings live under [settings.<module>]. A module reads them with
# module_setting, and ignores anything it does not recognise.
#
# [settings.git]
# signingkey = "ssh-ed25519 AAAA..."
FOOTER
  } >"$DOT_CONFIG"

  ok "wrote $DOT_CONFIG"
}
