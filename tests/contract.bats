#!/usr/bin/env bats
#
# The module contract.
#
# This file is what makes "the directory listing is the registry" safe. With
# no central manifest, nothing would otherwise stop a module from shipping a
# broken manifest, a missing field, or a symlink inside home/. The invariant
# is tested rather than remembered.
#
# It walks the same glob the driver walks, so a module cannot be exempt.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "there is at least one module" {
  run modules_all
  [ "${#lines[@]}" -gt 0 ]
}

@test "every module has a parseable manifest with its one field" {
  local name manifest
  while IFS= read -r name; do
    manifest="$DOT_ROOT/modules/$name/module.toml"
    run dasel -i toml -o yaml description <"$manifest"
    [ "$status" -eq 0 ] || {
      echo "module '$name' is missing field 'description'"
      return 1
    }
  done < <(modules_all)
}

@test "module names are lowercase, and match their directory" {
  local name
  while IFS= read -r name; do
    [[ $name =~ ^[a-z][a-z0-9-]*$ ]] || {
      echo "bad module name: '$name'"
      return 1
    }
  done < <(modules_all)
}

@test "manifests carry no second field" {
  # Field creep is the most likely path back to v1's feature.sh. A new field
  # is allowed, but only deliberately -- which means editing this test.
  # `default` went with the `custom` profile that read it; `order` went once
  # every module had settled on the same value; `sudo` went once it turned out
  # that no module ever needed root, which left `description` on its own.
  local name keys
  while IFS= read -r name; do
    keys=$(dasel -i toml -o yaml 'keys()' <"$(module_manifest "$name")" | sed 's/^- //' | sort | tr '\n' ' ')
    [ "$keys" = "description " ] || {
      echo "$name has unexpected manifest fields: $keys"
      return 1
    }
  done < <(modules_all)
}

@test "home/ contains no symlinks" {
  # A committed symlink would be linked to, producing a link to a link.
  local name found
  while IFS= read -r name; do
    found=$(find "$DOT_ROOT/modules/$name" -path '*/home/*' -type l 2>/dev/null)
    [ -z "$found" ] || {
      echo "$name has symlinks under home/: $found"
      return 1
    }
  done < <(modules_all)
}

@test "hooks source the library and are shellcheck-clean" {
  # Three hook names, and the list is closed. remove.sh joined it because the
  # symlink sweep in uninstall.sh cannot see a link pointing outside the repo
  # or a file the module generated; a fourth needs a gap that specific.
  local name hook path
  while IFS= read -r name; do
    for hook in apply.sh doctor.sh remove.sh; do
      path="$DOT_ROOT/modules/$name/$hook"
      [ -f "$path" ] || continue
      grep -q 'lib/dot.sh' "$path" || {
        echo "$name/$hook does not source lib/dot.sh"
        return 1
      }
      run shellcheck -x "$path"
      [ "$status" -eq 0 ] || {
        echo "$name/$hook fails shellcheck"
        echo "$output"
        return 1
      }
    done
  done < <(modules_all)
}

@test "no doctor.sh changes anything in \$HOME" {
  # `dot doctor` is the one verb that promises to change nothing, and a hook is
  # the easiest place to break that promise by accident -- the tool you ask
  # for a status is not obliged to answer without writing. `colima status`
  # CREATED ~/.colima/_lima before answering, so a doctor run on a machine that
  # had never used containers left a directory behind, and the uninstaller's
  # dry run then warned about a VM it had just conjured.
  #
  # Snapshotting $HOME around every hook catches the next one generically,
  # which is the only way this stays caught: the specific offender is one
  # command deep inside one module, and nothing else would have looked.
  local name before after
  before=$(home_snapshot)
  while IFS= read -r name; do
    [ -f "$DOT_ROOT/modules/$name/doctor.sh" ] || continue
    run env DOT_MODULE="$name" DOT_MODULE_DIR="$DOT_ROOT/modules/$name" \
      bash "$DOT_ROOT/modules/$name/doctor.sh"
  done < <(modules_all)
  after=$(home_snapshot)

  [ "$before" = "$after" ] || {
    echo "a doctor.sh wrote to \$HOME:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    return 1
  }
}

@test "every profile refers only to modules that exist" {
  local profile name
  while IFS= read -r profile; do
    while IFS= read -r name; do
      module_exists "$name" || {
        echo "profile '$profile' lists unknown module '$name'"
        return 1
      }
    done < <(toml_list "$DOT_ROOT/profiles.toml" "profiles[\"$profile\"]")
  done < <(toml_list "$DOT_ROOT/profiles.toml" 'profiles.keys()')
}

@test "every script with a shebang is executable" {
  # The shim exec's bin/dot directly, so a missing +x bit breaks the CLI with
  # a "Permission denied" that points at the shim rather than the cause.
  local found
  # `|| true`: the loop body's last iteration usually ends in a false test,
  # which under bats' errexit would abort the assignment itself.
  found=$(find "$DOT_ROOT" -path "$DOT_ROOT/.git" -prune -o \
    \( -name '*.sh' -o -name 'dot' \) -type f -print |
    while IFS= read -r f; do
      if head -1 "$f" | grep -q '^#!' && [ ! -x "$f" ]; then echo "$f"; fi
    done || true)
  [ -z "$found" ] || {
    echo "not executable: $found"
    return 1
  }
}

@test "Brewfiles exist only in core/ and modules/" {
  run bash -c "find '$DOT_ROOT' -name 'Brewfile*' -not -path '*/.git/*' | grep -cv -e '/core/' -e '/modules/'"
  [ "$output" = "0" ]
}

@test "a module contains no file the driver would ignore" {
  # THE FAILURE THIS EXISTS FOR. modules/ssh/config once sat at the top of its
  # module instead of in home/.ssh/, which is the only place fs_pairs looks. It
  # looked installed, it was inert, and nothing caught it: shellcheck does not
  # lint it, no hook sources it, and every other test here iterates a fixed
  # list of names and so never saw it. The module reported healthy while ssh
  # read no config at all.
  #
  # The names below are the whole vocabulary of a module directory -- the same
  # closed set modules/CLAUDE.md documents. Adding to it is meant to be a
  # deliberate edit here, in the open, exactly like adding a hook.
  local stray=()
  for path in "$DOT_ROOT"/modules/*/*; do
    case ${path##*/} in
      module.toml | Brewfile | README.md) ;;
      apply.sh | doctor.sh | remove.sh) ;;
      # home/ is a directory and its contents are mirrored verbatim, so nothing
      # inside it is checkable by name -- that is the point of it.
      home) [[ -d $path ]] || stray+=("${path#"$DOT_ROOT"/}") ;;
      *) stray+=("${path#"$DOT_ROOT"/}") ;;
    esac
  done

  [ ${#stray[@]} -eq 0 ] || {
    printf 'the driver reads none of these:\n'
    printf '  %s\n' "${stray[@]}"
    printf 'a config file belongs under the module home/, at its path in $HOME\n'
    return 1
  }
}
