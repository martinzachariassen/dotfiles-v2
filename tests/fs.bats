#!/usr/bin/env bats
#
# The symlink engine. These are the highest-value tests in the repo: this is
# the only code that moves and deletes files in $HOME, so every state it can
# encounter gets a test.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

# --- fs_classify ------------------------------------------------------------

@test "classify: missing when nothing is there" {
  run fs_classify /some/src "$HOME/.gitconfig"
  [ "$output" = "missing" ]
}

@test "classify: ok when the link already points at src" {
  local src="$DOT_TMP/src"
  echo hi >"$src"
  ln -s "$src" "$HOME/f"
  run fs_classify "$src" "$HOME/f"
  [ "$output" = "ok" ]
}

@test "classify: clobbered when a real file is in the way" {
  echo mine >"$HOME/f"
  run fs_classify "$DOT_TMP/src" "$HOME/f"
  [ "$output" = "clobbered" ]
}

@test "classify: wrong-target when the link points elsewhere" {
  echo a >"$DOT_TMP/a"
  echo b >"$DOT_TMP/b"
  ln -s "$DOT_TMP/b" "$HOME/f"
  run fs_classify "$DOT_TMP/a" "$HOME/f"
  [ "$output" = "wrong-target" ]
}

@test "classify: broken beats ok for a dangling link to src" {
  # The file was deleted from the repo. Reporting this as "ok" because the
  # target string still matches would hide the only interesting fact.
  local src="$DOT_TMP/gone"
  echo x >"$src"
  ln -s "$src" "$HOME/f"
  rm "$src"
  run fs_classify "$src" "$HOME/f"
  [ "$output" = "broken" ]
}

# --- fs_link ----------------------------------------------------------------

@test "link: creates the link and any missing parent directories" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config" "tracked"

  fs_link_tree "$m"

  [ -L "$HOME/.config/git/config" ]
  [ "$(cat "$HOME/.config/git/config")" = "tracked" ]
  [ "$DOT_N_LINKED" -eq 1 ]
}

@test "link: parent directories are real directories, never symlinks" {
  # If ~/.config were a link into the repo, one module would own the whole
  # tree and every other tool's files would disappear.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config"

  fs_link_tree "$m"

  [ -d "$HOME/.config" ]
  [ ! -L "$HOME/.config" ]
  [ ! -L "$HOME/.config/git" ]
}

@test "link: is idempotent and silent on the second run" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config"

  fs_link_tree "$m"
  DOT_N_LINKED=0 DOT_N_UNCHANGED=0
  fs_link_tree "$m"

  [ "$DOT_N_LINKED" -eq 0 ]
  [ "$DOT_N_UNCHANGED" -eq 1 ]
}

@test "link: a real file is moved to the backup tree, not overwritten" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo "precious" >"$HOME/.gitconfig"

  fs_link_tree "$m"

  [ -L "$HOME/.gitconfig" ]
  [ "$(cat "$HOME/.gitconfig")" = "from-repo" ]
  [ "$DOT_N_BACKED_UP" -eq 1 ]

  # The original still exists, exactly once, under the backup tree.
  run bash -c "grep -rl precious '$DOT_STATE/backups' | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}

@test "link: replaces a wrong-target link without making a backup" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo other >"$DOT_TMP/other"
  ln -s "$DOT_TMP/other" "$HOME/.gitconfig"

  fs_link_tree "$m"

  [ "$(readlink "$HOME/.gitconfig")" = "$m/home/.gitconfig" ]
  [ "$DOT_N_RELINKED" -eq 1 ]
  [ "$DOT_N_BACKED_UP" -eq 0 ]
  [ ! -d "$DOT_STATE/backups" ]
}

@test "link: repairs a broken link" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  ln -s "$DOT_TMP/never-existed" "$HOME/.gitconfig"

  fs_link_tree "$m"

  [ -e "$HOME/.gitconfig" ]
  [ "$DOT_N_RELINKED" -eq 1 ]
}

@test "link: a clean run leaves no backup directory behind" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"

  fs_link_tree "$m"

  [ ! -d "$DOT_STATE/backups" ]
}

@test "link: handles spaces in filenames" {
  local m
  m=$(fixture_module app)
  fixture_file "$m" ".config/some app/my config.toml" "ok"

  fs_link_tree "$m"

  [ -L "$HOME/.config/some app/my config.toml" ]
}

# --- dry run ----------------------------------------------------------------

@test "dry run: reports intent and changes nothing" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"
  export DOT_DRY_RUN=1

  fs_link_tree "$m"

  [ ! -e "$HOME/.gitconfig" ]
  [ "$DOT_N_LINKED" -eq 1 ]
}

@test "dry run: does not move a real file aside" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo precious >"$HOME/.gitconfig"
  export DOT_DRY_RUN=1

  fs_link_tree "$m"

  [ ! -L "$HOME/.gitconfig" ]
  [ "$(cat "$HOME/.gitconfig")" = "precious" ]
  [ ! -d "$DOT_STATE/backups" ]
}

# --- fs_check_tree ----------------------------------------------------------

@test "check: clean tree reports no drift" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig"
  fs_link_tree "$m"

  run fs_check_tree "$m"
  [ "$status" -eq 0 ]
}

@test "check: detects a clobbered file and never repairs it" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  fs_link_tree "$m"
  rm "$HOME/.gitconfig"
  echo replaced >"$HOME/.gitconfig"

  run fs_check_tree "$m"
  [ "$status" -eq 1 ]
  # doctor is read-only: the file must be exactly as we left it
  [ "$(cat "$HOME/.gitconfig")" = "replaced" ]
}

@test "check: an empty module is not drift" {
  local m
  m=$(fixture_module empty)
  run fs_check_tree "$m"
  [ "$status" -eq 0 ]
}

# --- fs_pairs ---------------------------------------------------------------

@test "pairs: maps home/ onto \$HOME literally" {
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".config/git/config"

  run fs_pairs "$m"
  [ "$output" = "$m/home/.config/git/config	$HOME/.config/git/config" ]
}

@test "pairs: a module with no home/ yields nothing" {
  local dir="$DOT_TMP/modules/macos"
  mkdir -p "$dir"
  run fs_pairs "$dir"
  [ -z "$output" ]
}
