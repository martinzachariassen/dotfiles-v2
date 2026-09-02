# shellcheck shell=bash
#
# Reading ~/.config/dotfiles/config.toml.
#
# There is deliberately no general writer here. The config is generated exactly
# once, by `dot config --init`, and belongs to the user from that moment on.
# Every tool that can write TOML (dasel included) rebuilds the file from its
# parsed form and drops comments, so the only way to keep a commented,
# hand-editable config honest is to never write it again.
#
# dasel v3 notes, verified against 3.11.2:
#   * no -f flag any more; input arrives on stdin
#   * -i is the INPUT format, not in-place editing (which v3 removed)
#   * a missing key exits 1, which is how defaults work below
#   * everything is read as -o yaml, scalars included: one output format means
#     one set of quoting rules to undo, in __cfg_unquote

cfg_exists() { [[ -f $DOT_CONFIG ]]; }

# Undo the quoting dasel's YAML output adds. YAML quotes only when leaving a
# value bare would be ambiguous, so almost everything falls straight through;
# the two cases that matter are an empty string ("") and a value containing
# ": ", which YAML single-quotes to stop it reading as a mapping.
#
# YAML's other escapes are deliberately absent. A tab comes back as a literal
# `\t` and a newline as a `|-` block, neither of which any setting this repo
# reads can contain -- a git identity, an SSH key, a directory name, a number.
# Adding them is also not the two-line change it looks like: these replacements
# run in sequence, and they are correct only because `\"` and `\\` cannot alias
# each other. A `\t` rule would rewrite the middle of a literal `\\t`, and
# config_generate now supports backslashes on purpose.
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
    line=$(__cfg_unquote "${line#- }")
    # `if`, not a trailing `&&`: a false test on the LAST line would leave the
    # loop -- and so the whole pipeline -- at status 1. See CLAUDE.md.
    if [[ -n $line ]]; then printf '%s\n' "$line"; fi
  done
}

# --- The user config, read through the generic reader above ----------------

cfg_get() { toml_get "$DOT_CONFIG" "$1" "${2:-}"; }
cfg_list() { toml_list "$DOT_CONFIG" "$1"; }

# cfg_parse_problems -- one line per sign that the config did not parse whole.
# Empty output means it did. Callers pick the severity: apply refuses, doctor
# reports.
#
# THE BUG THIS EXISTS FOR. dasel does not validate. On a malformed line it
# stops, keeps everything it read up to that point, and EXITS 0 -- so a missing
# comma in `enabled = [ "git", "zsh" "macos-defaults" ]` deletes the whole
# [modules] table from the parsed document while `schema` above it still reads
# fine. The old check queried `schema`, which is written by the generator ABOVE
# all user-editable content, so it could never fail on a hand-edit.
#
# What that costs is not a wrong value. With no enabled modules, every link in
# $HOME is unclaimed by definition, so `dot doctor` reports the user's entire
# working setup as orphaned and closes with `Remove with: rm <path>` -- a
# health check that tells you to delete your dotfiles because of a typo.
# `dot apply` agrees, prints "None enabled.", and exits 0.
#
# Two checks, because a real TOML parser is a dependency this repo does not
# have and neither check alone is enough:
cfg_parse_problems() {
  local -A seen=()
  local name

  while IFS= read -r name; do
    seen[$name]=1
  done < <(dasel -i toml -o yaml 'keys()' <"$DOT_CONFIG" 2>/dev/null | sed 's/^- //')

  # 1. Every table the file declares must be visible. A parse that stopped
  #    early cannot see the tables below where it stopped, and the file's own
  #    `[header]` lines are the one record of what was meant to be there.
  #
  #    Only the top-level name is taken (`[settings.git]` -> settings), and it
  #    is only ever COMPARED, never turned back into a selector -- which is
  #    what keeps dasel's dash-is-subtraction problem out of this. The pattern
  #    deliberately matches nothing exotic: a quoted or otherwise unusual table
  #    name is skipped rather than guessed at, because a doctor that cries wolf
  #    stops being read.
  while IFS= read -r name; do
    if [[ -z ${seen[$name]:-} ]]; then
      printf 'declares [%s] but the parser cannot see it -- syntax error above that line\n' "$name"
    fi
  done < <(sed -n 's/^\[\[*\([A-Za-z0-9_-]\{1,\}\)[].].*/\1/p' "$DOT_CONFIG" | sort -u)

  # 2. modules.enabled must be READABLE, which is not the same as non-empty.
  #    `enabled = []` is exactly what the `none` profile writes and is valid;
  #    a truncated config has no such key at all. That difference is the whole
  #    point -- it separates "nothing is enabled" from "nothing could be read",
  #    which are the two states the orphan report cannot tell apart on its own.
  #
  #    Guarded on [modules] being visible so a dropped table is reported once,
  #    by the check above, with the cause rather than the symptom.
  if [[ -n ${seen[modules]:-} ]] &&
    ! dasel -i toml -o yaml 'modules.enabled' <"$DOT_CONFIG" >/dev/null 2>&1; then
    printf 'has a [modules] table with no readable `enabled` list\n'
  fi
}
# Residual, stated rather than hidden: a typo inside the LAST table in the file
# drops only that table's remaining scalars, and nothing above notices. The
# damage is bounded to those values -- a signing key that silently stops being
# used, say -- and closing it needs a real parser.

# --- The one writer --------------------------------------------------------

# __cfg_quote VALUE -- VALUE as a TOML basic string, brackets included.
#
# The wizard offers your global git identity as the default, so this takes
# whatever `git config user.name` returns -- and `Martin "Zach" Z` is a real
# name shape. Interpolated raw it wrote `name  = "Martin "Zach" Z"`, and dasel
# stops parsing at the stray quote: the [modules] table BELOW it disappeared
# from the parsed document entirely. First run, nothing typed wrong, and the
# config the tool just wrote for you enables nothing.
#
# Backslash first, or the escape added for a quote would itself be escaped.
__cfg_quote() {
  local v=$1
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  printf '"%s"' "$v"
}
#
# config_generate NAME EMAIL MODULES -- create config.toml, once, at
# `dot config --init`. Afterwards the file is yours and nothing here rewrites
# it: that is what lets the comments below survive, and why enabling a module
# later is an edit rather than a wizard re-run. Refuses to clobber.
config_generate() {
  local name=$1 email=$2 modules=$3 signingkey=${4:-} line

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

    printf '[user]\nname  = %s\nemail = %s\n\n' \
      "$(__cfg_quote "$name")" "$(__cfg_quote "$email")"

    printf '[modules]\n'
    printf '# Add or remove names, then run `dot apply`.\n'
    printf '# Available: %s\n' "$(modules_all | tr '\n' ' ' | sed 's/ $//')"
    printf 'enabled = [\n'
    # `if`, not a trailing `&&` -- the same landmine as in toml_list.
    # Module names are validated elsewhere, but quoted through the same helper
    # so there is one answer to "how does a value get into this file".
    while IFS= read -r line; do
      if [[ -n $line ]]; then printf '  %s,\n' "$(__cfg_quote "$line")"; fi
    done <<<"$modules"
    printf ']\n\n'

    cat <<'FOOTER'
# Per-module settings live under [settings.<module>]. A module reads them with
# module_setting, and ignores anything it does not recognise.
FOOTER

    # The signing key is the PUBLIC half of a 1Password-held SSH key, so it
    # ships in profiles.toml and lands here ready to use -- there is nothing to
    # protect in it (GitHub serves everyone's at /<user>.keys). Written through
    # __cfg_quote like every other value: it is user-supplied as far as this
    # function knows, and one stray quote deletes the tables below it.
    if [[ -n $signingkey ]]; then
      printf '\n[settings.git]\nsigningkey = %s\n' "$(__cfg_quote "$signingkey")"
    else
      printf '#\n# [settings.git]\n# signingkey = "ssh-ed25519 AAAA..."\n'
    fi
  } >"$DOT_CONFIG"

  ok "wrote $DOT_CONFIG"
}
