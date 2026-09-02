#!/usr/bin/env bats
#
# modules/ghostty/doctor.sh -- the outranked-config check.
#
# Worth its own file for the same reason tests/zsh.bats is: the failure is
# invisible by construction. Ghostty reads four paths and the last one wins, so
# a file left in any of the other three silently beats the one this repo links
# -- and Ghostty's own error omits the filename when two of them disagree.
#
# Nothing generic can catch that. fs_check_tree and the orphan scan only look
# at paths some module claims, and this module claims exactly one of the four.
# If this check regresses to passing silently, the symptom is a config file
# under version control that has no effect on the terminal you are looking at.
#
# The hook is executed, not sourced -- exactly as lib/modules.sh runs it.
#
# FIXTURES MUST BE EMPTY OR VALID. doctor.sh also shells out to
# `ghostty +validate-config`, which on a developer machine really runs against
# the sandbox; a fixture containing junk would fail validation and these tests
# would be asserting on the wrong branch.

load helper

setup() {
  setup_sandbox
  mkdir -p "$HOME/.config/ghostty"
  mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
}
teardown() { teardown_sandbox; }

doctor() { run "$BASH" "$DOT_ROOT/modules/ghostty/doctor.sh"; }

# The three paths that outrank ~/.config/ghostty/config.ghostty, in load order.
legacy() { printf '%s\n' "$HOME/.config/ghostty/config"; }
app_new() { printf '%s\n' "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; }
app_old() { printf '%s\n' "$HOME/Library/Application Support/com.mitchellh.ghostty/config"; }

@test "a clean home reports nothing outranking the repo" {
  doctor
  [[ $output == *"nothing outranks"* ]]
  [[ $output != *"read after"* ]]
}

@test "the legacy ~/.config/ghostty/config is reported" {
  : >"$(legacy)"
  doctor
  [[ $output == *"~/.config/ghostty/config is read after"* ]]
  [[ $output != *"nothing outranks"* ]]
}

@test "an Application Support config.ghostty is reported" {
  : >"$(app_new)"
  doctor
  [[ $output == *"Application Support"* ]]
  [[ $output == *"read after"* ]]
}

@test "an Application Support config is reported" {
  : >"$(app_old)"
  doctor
  [[ $output == *"Application Support"* ]]
  [[ $output == *"read after"* ]]
}

@test "all three are reported, and in the order Ghostty loads them" {
  : >"$(legacy)"
  : >"$(app_new)"
  : >"$(app_old)"
  doctor

  # The LAST one named is the one actually in charge, so the order carries
  # meaning -- a set of warnings sorted any other way would be misleading.
  local seen
  seen=$(grep -c 'read after' <<<"$output")
  [ "$seen" -eq 3 ]

  local first last
  first=$(grep -n 'read after' <<<"$output" | head -1)
  last=$(grep -n 'read after' <<<"$output" | tail -1)
  [[ $first == *".config/ghostty/config is read after"* ]]
  [[ $last == *"com.mitchellh.ghostty/config is read after"* ]]
}

@test "an outranked config tells you what to do about it" {
  : >"$(legacy)"
  doctor
  [[ $output == *"config.ghostty"* ]]
  [[ $output == *"delete the file"* ]]
}

@test "an outranked config never exits clean" {
  # Deliberately not asserting the number. Whether this run warns (3) or the
  # validator also failed (1) depends on whether Ghostty is installed on the
  # machine running the suite; what must hold either way is that `dot doctor`
  # does not call this healthy.
  : >"$(legacy)"
  doctor
  [ "$status" -ne 0 ]
}

@test "the hook writes nothing to \$HOME" {
  # contract.bats asserts this across every module, but this one shells out to
  # a FOREIGN BINARY -- `ghostty +validate-config` is not ours and its
  # read-onlyness is an assumption, not a promise. Asserted here too so the
  # failure names the module that broke it.
  local before after
  before=$(home_snapshot)
  doctor
  after=$(home_snapshot)
  [ "$before" = "$after" ]
}

@test "the config the module links is the one Ghostty reads first" {
  # Guards the filename, not the contents. `config` and `config.ghostty` are
  # both valid names and the plain one wins, so shipping the wrong one would
  # make the module lose to any leftover the doctor is meant to warn about.
  [ -f "$DOT_ROOT/modules/ghostty/home/.config/ghostty/config.ghostty" ]
  [ ! -e "$DOT_ROOT/modules/ghostty/home/.config/ghostty/config" ]
}

@test "the config has no trailing comments" {
  # `key = value  # note` is a PARSE ERROR in Ghostty, not a comment, and the
  # resulting startup dialog is redacted to <private> on macOS. Cheap to check
  # here; expensive to diagnose there.
  local offenders
  offenders=$(grep -nE '^[^#]+[[:space:]]#' \
    "$DOT_ROOT/modules/ghostty/home/.config/ghostty/config.ghostty" || true)
  [ -z "$offenders" ] || {
    echo "trailing comments are parse errors in Ghostty:"
    echo "$offenders"
    return 1
  }
}
