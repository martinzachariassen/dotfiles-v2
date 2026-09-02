#!/usr/bin/env bats
#
# modules/ssh -- the socket, and the config that names it.
#
# The module is two halves that must agree and cannot see each other: a tracked
# ~/.ssh/config carrying an IdentityAgent line, and a doctor.sh that checks
# whether anything is listening there. doctor.sh says so itself -- "THE TWO
# MUST AGREE" -- and until this file nothing held them to it. Change the path
# on one side and the check goes on passing against the old socket while ssh
# reads the new one, which is the single way that hook could be worse than no
# hook at all.
#
# Nothing below writes the socket path down. Both sides are extracted from the
# files themselves, because a constant here would be the third copy.

load helper

setup() {
  setup_sandbox
  SSH_CONFIG="$DOT_ROOT/modules/ssh/home/.ssh/config"
  DOCTOR="$DOT_ROOT/modules/ssh/doctor.sh"
}

teardown() { teardown_sandbox; }

# The socket doctor.sh will test, with $HOME resolved to the argument. Textual
# substitution rather than eval: the value is a path out of a tracked file, and
# eval on it would be a habit worth not forming.
doctor_socket() {
  local s
  s=$(sed -n 's/^sock="\(.*\)"$/\1/p' "$DOCTOR")
  printf '%s\n' "${s//\$HOME/$1}"
}

doctor() {
  run env HOME="${1:-$HOME}" DOT_ROOT="$DOT_ROOT" "$BASH" "$DOCTOR"
}

# --- the invariant ----------------------------------------------------------

@test "the socket doctor.sh checks is the one ssh is told to use" {
  local from_config from_doctor
  from_config=$(sed -n 's/^[[:space:]]*IdentityAgent[[:space:]]\{1,\}//p' \
    "$SSH_CONFIG" | tr -d '"')
  from_config=${from_config/#\~/$HOME}
  from_doctor=$(doctor_socket "$HOME")

  # Both non-empty first, or a rename makes this pass over nothing, forever,
  # without saying so -- the failure mode of every derived assertion.
  [ -n "$from_config" ] || {
    echo 'no IdentityAgent line in the shipped ssh config'
    return 1
  }
  [ -n "$from_doctor" ] || {
    echo 'no sock= assignment in ssh/doctor.sh'
    return 1
  }
  [ "$from_config" = "$from_doctor" ] || {
    echo "config: $from_config"
    echo "doctor: $from_doctor"
    return 1
  }
}

# --- doctor.sh --------------------------------------------------------------

@test "doctor: a live agent socket passes" {
  command -v python3 >/dev/null || skip 'no python3 to make a unix socket'

  # A SHORT $HOME on purpose. A unix socket path is capped at 104 bytes on
  # macOS, and the sandbox's mktemp path plus "Library/Group Containers/..."
  # goes past it -- bind() would fail and the test would read as a doctor bug.
  local short sock
  short=$(mktemp -d /tmp/dot-ssh.XXXXXX)
  sock=$(doctor_socket "$short")
  mkdir -p "$(dirname "$sock")"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sock"

  doctor "$short"
  rm -rf "$short"

  [ "$status" -eq 0 ]
  [[ $output == *"live"* ]]
}

@test "doctor: a missing socket warns without failing" {
  # The state of every machine where the 1Password setting has not been ticked.
  # WARN and not failure: nothing is broken, there is something to do.
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"not running"* ]]
  [[ $output == *"Developer"* ]]
}

@test "doctor: an ordinary file at the socket path is not healthy" {
  # -S, not -e. A regular file there means something went wrong in a way -e
  # would call fine, and the entire value of this hook is naming a failure that
  # otherwise surfaces as "Permission denied (publickey)".
  local sock
  sock=$(doctor_socket "$HOME")
  mkdir -p "$(dirname "$sock")"
  printf 'not a socket\n' >"$sock"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
}

# --- what the module actually ships -----------------------------------------

@test "syntax: the shipped ssh config parses" {
  # `make check` runs shellcheck and shfmt over *.sh, and this file is neither
  # -- the same gap zsh.bats closes for the zsh files. A bad keyword here is
  # not a warning: ssh exits 255 and EVERY connection stops, including the one
  # you would pull the fix with. -G resolves the config without connecting.
  command -v ssh >/dev/null || skip 'no ssh on this machine'
  run ssh -G -F "$SSH_CONFIG" github.com
  [ "$status" -eq 0 ] || {
    echo "$output"
    return 1
  }
}

@test "the config actually points github.com at an agent" {
  # Parsing is not matching. A `Host github.com-work` typo parses perfectly and
  # silently applies to nothing, which is the inert-config failure that put the
  # stray-file check into contract.bats in the first place.
  command -v ssh >/dev/null || skip 'no ssh on this machine'
  run ssh -G -F "$SSH_CONFIG" github.com
  local resolved
  resolved=$(printf '%s\n' "$output" | sed -n 's/^identityagent //p')
  [ -n "$resolved" ]
  [ "$resolved" != none ]
}
