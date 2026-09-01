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

@test "every module has a parseable manifest with all three fields" {
  local name manifest
  while IFS= read -r name; do
    manifest="$DOT_ROOT/modules/$name/module.toml"
    for field in description order sudo; do
      run dasel -i toml -o json "$field" <"$manifest"
      [ "$status" -eq 0 ] || {
        echo "module '$name' is missing field '$field'"
        return 1
      }
    done
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

@test "order is an integer and sudo is a boolean" {
  local name order sdo
  while IFS= read -r name; do
    order=$(module_order "$name")
    [[ $order =~ ^[0-9]+$ ]] || {
      echo "$name: order '$order' is not an integer"
      return 1
    }
    sdo=$(toml_get "$(module_manifest "$name")" sudo)
    [[ $sdo == true || $sdo == false ]] || {
      echo "$name: sudo must be a boolean"
      return 1
    }
  done < <(modules_all)
}

@test "manifests carry no fourth field" {
  # Field creep is the most likely path back to v1's feature.sh. A new field
  # is allowed, but only deliberately -- which means editing this test.
  # `default` was removed once its only reader, the `custom` profile, went.
  local name keys
  while IFS= read -r name; do
    keys=$(dasel -i toml -o yaml 'keys()' <"$(module_manifest "$name")" | sed 's/^- //' | sort | tr '\n' ' ')
    [ "$keys" = "description order sudo " ] || {
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
  local name hook path
  while IFS= read -r name; do
    for hook in apply.sh doctor.sh; do
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

@test "every profile refers only to modules that exist" {
  local profile name
  while IFS= read -r profile; do
    while IFS= read -r name; do
      module_exists "$name" || {
        echo "profile '$profile' lists unknown module '$name'"
        return 1
      }
    done < <(toml_list "$DOT_ROOT/profiles.toml" "profiles.$profile")
  done < <(toml_list "$DOT_ROOT/profiles.toml" 'profiles.keys()')
}

@test "modules sort by order then name" {
  run bash -c "printf 'macos-defaults\ngit\nzsh\n' | { source '$DOT_ROOT/lib/dot.sh'; modules_sort; }"
  [ "${lines[0]}" = "zsh" ]            # order 10
  [ "${lines[1]}" = "git" ]            # order 50
  [ "${lines[2]}" = "macos-defaults" ] # order 90
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
