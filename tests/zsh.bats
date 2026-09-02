#!/usr/bin/env bats
#
# modules/zsh/doctor.sh -- the stray-config check.
#
# Worth its own file because the thing it guards is invisible by construction:
# an installer appending to a $HOME/.zshrc that ZDOTDIR has taken out of the
# read path. If this check ever regresses to passing silently, the symptom is a
# tool that is missing from every shell for no stated reason.
#
# The hook is executed, not sourced -- exactly as lib/modules.sh runs it -- so
# what these tests assert is the real contract: what it prints, and the exit
# status the driver folds back in.

load helper

setup() {
  setup_sandbox
  # Pinned rather than inherited: a real XDG_CONFIG_HOME in the developer's
  # environment would send DOT_CONFIG_HOME outside the sandbox.
  export XDG_CONFIG_HOME="$HOME/.config"
}
teardown() { teardown_sandbox; }

doctor() { run env -u ZDOTDIR "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"; }

@test "clean home passes" {
  doctor
  [ "$status" -eq 0 ]
  [[ $output == *"no dead config"* ]]
}

@test "a stray ~/.zshrc warns, and the warning reaches the driver" {
  # The shape of the real bug: something appended to a file nobody reads.
  printf 'eval "$(some-tool init zsh)"\n' >"$HOME/.zshrc"

  doctor
  # DOT_STATUS_WARN. Not 1: nothing is broken, and `dot doctor && ...` must
  # keep working. Not 0: fold_status has to see that something was said.
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *".zshrc"* ]]
  [[ $output == *"local.zsh"* ]]
}

@test "every file zsh would read from ZDOTDIR is reported" {
  local f
  for f in .zshrc .zprofile .zlogin .zlogout; do
    printf 'x\n' >"$HOME/$f"
  done

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  for f in .zshrc .zprofile .zlogin .zlogout; do
    [[ $output == *"$f"* ]] || {
      echo "$f not reported"
      return 1
    }
  done
}

@test "~/.zshenv is not a stray -- it is the one file that belongs there" {
  printf 'export ZDOTDIR=...\n' >"$HOME/.zshenv"
  doctor
  [ "$status" -eq 0 ]
}

@test "a hijacked ZDOTDIR is reported" {
  # Without this the stray check would be backwards: if ZDOTDIR points
  # somewhere else, $HOME/.zshrc is live and deleting it is the wrong advice.
  run env ZDOTDIR="$HOME/elsewhere" "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"ZDOTDIR is $HOME/elsewhere"* ]]
}

@test "an unset ZDOTDIR is not an accusation" {
  # doctor run from bash, cron or CI cannot observe it. Silence is correct.
  doctor
  [[ $output != *"ZDOTDIR is "*", expected"* ]]
}

# --- What the module actually ships ------------------------------------------

@test "syntax: every zsh file this module links parses" {
  # The gap this closes: `make check` runs shellcheck and shfmt over *.sh, and
  # these are the only files in the repo that are neither. So a stray `fi` in
  # .zshrc passes CI, links cleanly, and the symptom arrives on the next machine
  # to open a shell -- including the shell you would want to fix it from.
  #
  # `zsh -n` parses without executing, which is the only safe way to ask: these
  # files run `eval`, set PATH and start a prompt.
  command -v zsh >/dev/null || skip 'no zsh on this machine'

  local f checked=0
  while IFS= read -r f; do
    checked=$((checked + 1))
    run zsh -n "$f"
    [ "$status" -eq 0 ] || {
      echo "zsh -n rejected ${f#"$DOT_ROOT"/}:"
      echo "$output"
      return 1
    }
  done < <(find "$DOT_ROOT/modules/zsh/home" -type f)

  # Or a rename makes this pass over nothing, forever, without saying so.
  [ "$checked" -gt 0 ]
}
