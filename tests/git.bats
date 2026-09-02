#!/usr/bin/env bats
#
# modules/git/apply.sh -- the only module that GENERATES a file instead of
# linking one.
#
# That is what earns it a file here. A linked module is verified generically by
# fs_check_tree; config.local is printf output, so nothing but this stands
# between a quoting bug and a git identity that is not yours -- or between a
# missing signer and a repo you cannot commit to at all.

load helper

setup() {
  setup_sandbox

  # Stand-in for 1Password's signer. The real one lives inside an .app bundle
  # no CI machine has, and the branch it gates is the point of half this file,
  # which is why apply.sh takes the path as an input rather than a constant.
  OPSIGN="$DOT_TMP/op-ssh-sign"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$OPSIGN"
  chmod +x "$OPSIGN"

  DEST="$HOME/.config/git/config.local"
}

teardown() { teardown_sandbox; }

# The real chain, not a hand-written TOML string: on a first run these values
# come from profiles.toml through config_generate, and its quoting is part of
# what is under test here.
with_config() { config_generate "$1" "$2" 'git' "${3:-}" >/dev/null; }

# apply [DRY_RUN] [SIGNER] -- SIGNER unset means the stub. Pass a path that does
# not exist to model a machine without 1Password.
apply() {
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    DOT_OP_SSH_SIGN="${2-$OPSIGN}" \
    "$BASH" "$DOT_ROOT/modules/git/apply.sh"
}

remove() {
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" DOT_CONFIG="$DOT_CONFIG" \
    DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    "$BASH" "$DOT_ROOT/modules/git/remove.sh"
}

# Ask git, not grep. What matters is the value git PARSES back out -- grep would
# pass happily on a file whose quoting silently truncates the name.
gitcfg() { git config --file "$DEST" --get "$1"; }

# --- identity ---------------------------------------------------------------

@test "identity: name and email reach the file git will read" {
  with_config 'Ada Lovelace' 'ada@example.com'
  apply
  [ "$status" -eq 0 ]
  [ "$(gitcfg user.name)" = 'Ada Lovelace' ]
  [ "$(gitcfg user.email)" = 'ada@example.com' ]
}

@test "identity: a name containing # and a quote survives git's parser" {
  # Unquoted, `#` starts a comment and a bare `"` is stripped, so this name
  # reads back as `Martin` -- silently, and plausibly enough that you would not
  # notice until it was on a commit. config_generate quotes it into TOML and
  # q() quotes it into git config; this asserts the whole chain, not one half.
  with_config 'Martin # "Zach" \ Z' 'm@example.com'
  apply
  [ "$status" -eq 0 ]
  [ "$(gitcfg user.name)" = 'Martin # "Zach" \ Z' ]
}

@test "identity: an empty one warns and writes no file at all" {
  printf 'schema = 1\n\n[user]\nname  = ""\nemail = ""\n\n[modules]\nenabled = ["git"]\n' \
    >"$DOT_CONFIG"
  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"user.name"* ]]
  [ ! -e "$DEST" ]
}

# --- signing ----------------------------------------------------------------

@test "signing: a key and a signer write the whole block" {
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  apply
  [ "$status" -eq 0 ]
  [ "$(gitcfg user.signingkey)" = 'ssh-ed25519 AAAAKEY' ]
  [ "$(gitcfg gpg.format)" = 'ssh' ]
  [ "$(gitcfg commit.gpgsign)" = 'true' ]
  # THE LINE THIS FILE EXISTS FOR. Without it git falls back to `ssh-keygen -Y
  # sign`, which does not read ~/.ssh/config -- so the IdentityAgent line the
  # entire ssh module ships is invisible and every commit dies on `No private
  # key found`, while `git push` and ssh/doctor.sh both report healthy.
  [ "$(gitcfg gpg.ssh.program)" = "$OPSIGN" ]
}

@test "signing: no signer disables signing instead of breaking every commit" {
  # `gpgsign = true` aimed at a signer that is not installed does not give you
  # unsigned commits, it gives you none. The apps cask may not have landed when
  # this hook first runs, so off-with-a-warning is the recoverable choice.
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  apply 0 "$DOT_TMP/not-installed"

  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"1Password"* ]]

  # None of the three, or the commit path is merely broken in a new way.
  run gitcfg commit.gpgsign
  [ "$status" -ne 0 ]
  run gitcfg gpg.format
  [ "$status" -ne 0 ]
  run gitcfg gpg.ssh.program
  [ "$status" -ne 0 ]

  # And the identity half is untouched: you can still commit, just unsigned.
  [ "$(git config --file "$DEST" --get user.name)" = 'Ada' ]
}

@test "signing: no key means no signing block, and nothing to warn about" {
  with_config 'Ada' 'ada@example.com'
  apply
  [ "$status" -eq 0 ]
  run gitcfg commit.gpgsign
  [ "$status" -ne 0 ]
}

@test "signing: an advisory never lands inside the generated file" {
  # `dim` and `info` print to STDOUT, and stdout inside the generator block is
  # config.local itself -- so a helpfully-worded line added in the wrong place
  # becomes a git config syntax error. Parsing the whole file catches it
  # generically, which naming the expected keys would not.
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  apply 0 "$DOT_TMP/not-installed"
  run git config --file "$DEST" --list
  [ "$status" -eq 0 ]
}

# --- dry run ----------------------------------------------------------------

@test "dry run: announces the write and makes none" {
  with_config 'Ada' 'ada@example.com' 'ssh-ed25519 AAAAKEY'
  local before
  before=$(home_snapshot)
  apply 1
  [ "$status" -eq 0 ]
  [[ $output == *"config.local"* ]]
  [ "$(home_snapshot)" = "$before" ]
}

# --- remove.sh --------------------------------------------------------------

@test "remove: takes back the file apply generated" {
  with_config 'Ada' 'ada@example.com'
  apply
  [ -f "$DEST" ]
  remove
  [ "$status" -eq 0 ]
  [ ! -e "$DEST" ]
}

@test "remove: leaves a config.local this repo did not write" {
  # config.local is the conventional name for "the git config I keep off
  # GitHub", so one may well predate the module at this path. The generated
  # header is the only proof of ownership there is.
  mkdir -p "$(dirname "$DEST")"
  printf '[user]\n\tname = Someone Else\n' >"$DEST"
  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [ "$(git config --file "$DEST" --get user.name)" = 'Someone Else' ]
}
