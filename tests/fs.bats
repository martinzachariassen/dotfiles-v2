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

@test "link: a directory in the way is called a directory, and still moved aside" {
  # The message said "(real file in the way)" whatever was actually there, and
  # a whole directory going into the backup tree is by far the bigger surprise
  # of the two -- the case where you most want the report to be precise about
  # what it just moved.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  mkdir -p "$HOME/.gitconfig"
  printf 'mine\n' >"$HOME/.gitconfig/inside.txt"

  run fs_link_tree "$m"
  [[ $output == *"real directory in the way"* ]]
  [[ $output != *"real file in the way"* ]]

  # `run` is a subshell, so the tallies are gone -- but its writes to disk are
  # real, which is the half this asserts on.
  [ -L "$HOME/.gitconfig" ]
  [ "$(cat "$HOME/.gitconfig")" = "from-repo" ]

  # The directory went in whole: its contents are still there, exactly once.
  run bash -c "grep -rl mine '$DOT_STATE/backups' | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}

@test "backup: the run remembers where it put things" {
  # fs_backup_dir was called as `$(fs_backup_dir)`, and a command substitution
  # is a subshell -- so the memoised path never reached the caller. Everything
  # downstream that reads the variable silently stopped working.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo "precious" >"$HOME/.gitconfig"

  fs_link_tree "$m"

  [ -n "$__DOT_BACKUP_DIR" ]
  fs_backup_used
}

@test "report: says where the replaced files went" {
  # The visible symptom: a run announced "1 backed up" and then never told you
  # where the file had gone, because fs_backup_used tested a variable the
  # subshell had thrown away.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  echo "precious" >"$HOME/.gitconfig"

  fs_link_tree "$m"
  run fs_report

  [[ $output == *"1 backed up"* ]]
  [[ $output == *"Replaced files were moved to $DOT_STATE/backups/"* ]]
}

@test "backup: one run uses one directory, even across a second boundary" {
  # The silent half of the same bug. Every collision re-ran `date`, so two
  # files backed up on either side of a second landed in two different
  # timestamped directories -- and restoring by hand then means knowing to
  # look in more than one place. The sleep is the point of the test.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  fixture_file "$m" ".gitignore" "from-repo"
  echo "precious-one" >"$HOME/.gitconfig"
  echo "precious-two" >"$HOME/.gitignore"

  fs_link "$m/home/.gitconfig" "$HOME/.gitconfig"
  sleep 1.1
  fs_link "$m/home/.gitignore" "$HOME/.gitignore"

  [ "$DOT_N_BACKED_UP" -eq 2 ]
  run bash -c "find '$DOT_STATE/backups' -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '"
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

@test "check: a directory in the way is reported as a directory" {
  # The same wording bug as fs_link's, one verb over -- doctor has its own copy
  # of the label, so fixing one would have left the other lying.
  local m
  m=$(fixture_module git)
  fixture_file "$m" ".gitconfig" "from-repo"
  mkdir -p "$HOME/.gitconfig"

  run fs_check_tree "$m"
  [ "$status" -eq 1 ]
  [[ $output == *"real directory"* ]]
  [[ $output != *"real file"* ]]
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

# --- fs_report --------------------------------------------------------------

@test "report: several tallies are joined with a comma AND a space" {
  # Regression: this was `IFS=', '; printf '%s' "${parts[*]}"`, and ${arr[*]}
  # joins on only the FIRST character of IFS -- so the summary of a real run
  # read "3 linked,3 backed up".
  DOT_N_LINKED=3
  DOT_N_BACKED_UP=2
  run fs_report
  [[ $output == *"3 linked, 2 backed up"* ]]
}

@test "report: a single tally gets no separator" {
  DOT_N_LINKED=1
  run fs_report
  [[ $output == *"1 linked"* ]]
  [[ $output != *","* ]]
}

@test "report: nothing done says so" {
  run fs_report
  [[ $output == *"No files to link."* ]]
}
