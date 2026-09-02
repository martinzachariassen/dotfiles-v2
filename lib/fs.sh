# shellcheck shell=bash
#
# The symlink engine: the correctness core of this repo. Everything else can be
# rewritten on a whim; a bug in here loses files.
#
# Two rules govern the whole design:
#
#   1. Directories are NEVER symlinked, only traversed. If ~/.config were a
#      link into the repo, one module would own the entire tree and every other
#      tool's files would vanish from view. Only leaf files are linked.
#
#   2. A real file is never destroyed. It is MOVED to the backup tree, so after
#      a collision the file is in exactly one place -- not two, with no way to
#      tell which one you have been editing.

# Tallies for the end-of-run report. Apply-side only: the removal helpers below
# keep no tally, because a driver-side counter could only ever report the
# removals the DRIVER made. Module remove.sh hooks are separate processes, so
# theirs would be missing from it -- and an undercount at the bottom of an
# uninstall is worse than the per-line narration those helpers already print.
DOT_N_LINKED=0
DOT_N_RELINKED=0
DOT_N_BACKED_UP=0
DOT_N_UNCHANGED=0

# fs_backup_dir -- this run's backup directory, created on first use so a clean
# run leaves no empty directory behind.
#
# DERIVED FROM AN INHERITED ID, NOT MEMOISED, and that is the fix for two
# separate bugs with the same root. Memoising into a variable meant the answer
# could not survive a subshell -- called as `$(fs_backup_dir)`, every collision
# re-ran `date` and scattered one run's backups across a directory per second.
# Fixing that by assigning to a global fixed the subshell but not the PROCESS
# boundary: a hook is its own process, so a file that containers/apply.sh moved
# aside went into a directory the driver had never heard of, and the summary
# reported no backups at all. DOT_RUN_ID is exported, so every process in the
# run computes the same path without anyone having to remember it.
fs_backup_dir() {
  local dir="$DOT_STATE/backups/$DOT_RUN_ID"
  [[ $DOT_DRY_RUN == 1 ]] || mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# Whether anything was moved aside this run -- by this process or by a hook it
# ran. The directory on disk is the only evidence that crosses the process
# boundary; the tally covers a dry run, where by definition there is none.
fs_backup_used() {
  ((DOT_N_BACKED_UP)) || [[ -d "$DOT_STATE/backups/$DOT_RUN_ID" ]]
}

# fs_pairs DIR -- emit "src<TAB>dst" for every leaf file under DIR/home.
#
# The single place that knows how a module's home/ tree maps onto $HOME, so
# apply and doctor can never disagree about what is expected on disk.
fs_pairs() {
  local dir=$1 home="$1/home" src rel
  [[ -d $home ]] || return 0
  # -print0 / `read -d ''` separate paths with a zero byte, the one character a
  # filename cannot contain -- so a path with a newline in it cannot split.
  while IFS= read -r -d '' src; do
    rel=${src#"$home"/}
    printf '%s\t%s\n' "$src" "$HOME/$rel"
  done < <(find "$home" -type f -print0 | sort -z)
}

# fs_classify SRC DST -- one word describing what is at DST right now.
#
#   ok            symlink pointing at SRC, and SRC exists
#   missing       nothing there
#   wrong-target  symlink pointing somewhere else
#   clobbered     a real file or directory (you, or an installer, replaced it)
#   broken        symlink to a path that does not exist
#
# Dangling is checked before target equality on purpose: a link that points at
# SRC but resolves to nothing means SRC was deleted from the repo, and calling
# that "ok" would hide the very thing worth reporting.
fs_classify() {
  local src=$1 dst=$2
  if [[ -L $dst ]]; then
    if [[ ! -e $dst ]]; then
      printf 'broken\n'
    elif [[ $(readlink "$dst") == "$src" ]]; then
      printf 'ok\n'
    else
      printf 'wrong-target\n'
    fi
  elif [[ -e $dst ]]; then
    printf 'clobbered\n'
  else
    printf 'missing\n'
  fi
}

# fs_link SRC DST -- make DST a symlink to SRC, whatever state it is in now.
# Idempotent: an already-correct link prints nothing and touches nothing.
fs_link() {
  local src=$1 dst=$2 rel=${2#"$HOME"/} state backup what

  state=$(fs_classify "$src" "$dst")

  if [[ $state == ok ]]; then
    DOT_N_UNCHANGED=$((DOT_N_UNCHANGED + 1))
    return 0
  fi

  # Announce the intent first, so a dry run and a real run describe the change
  # in exactly the same words -- the report cannot drift from the action.
  case $state in
    missing) info "link    ~/$rel" ;;
    wrong-target | broken) info "relink  ~/$rel" ;;
    clobbered)
      # "file" is a lie when a whole directory is being moved aside, and that
      # is by far the bigger surprise of the two. Quoted because `file` is also
      # a command name, which shellcheck reads a bare word as (SC2209).
      if [[ -d $dst ]]; then what='directory'; else what='file'; fi
      info "backup  ~/$rel  (real $what in the way)"
      ;;
  esac
  [[ $DOT_DRY_RUN == 1 ]] || {
    # A real file is moved aside; a symlink carries no data, so replacing one
    # needs no backup.
    if [[ $state == clobbered ]]; then
      backup="$(fs_backup_dir)/$rel"
      mkdir -p "$(dirname "$backup")"
      mv "$dst" "$backup"
    else
      rm -f "$dst"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
  }

  case $state in
    missing) DOT_N_LINKED=$((DOT_N_LINKED + 1)) ;;
    wrong-target | broken) DOT_N_RELINKED=$((DOT_N_RELINKED + 1)) ;;
    clobbered) DOT_N_BACKED_UP=$((DOT_N_BACKED_UP + 1)) ;;
  esac
}

# fs_link_tree DIR -- link every file in DIR/home into $HOME.
#
# Says something ONLY when it did nothing, which is the case fs_link cannot
# cover: every change announces itself above, so a converged module printed an
# empty section under its heading -- the same silence `dot doctor` had to fix
# with 'all linked'. Six of eight modules looked like a step that died quietly.
#
# Phrased from the pre-state, not from what was done, so a dry run and a real
# run still produce identical words (the property tests/fs.bats pins).
fs_link_tree() {
  local src dst n=0 before=$DOT_N_UNCHANGED
  while IFS=$'\t' read -r src dst; do
    fs_link "$src" "$dst"
    n=$((n + 1))
  done < <(fs_pairs "$1")

  if ((n > 0 && DOT_N_UNCHANGED - before == n)); then
    ok "files        all $n already linked"
  fi
}

# --- Removal ----------------------------------------------------------------
#
# The two halves of an uninstall, kept apart on purpose. Everything this repo
# puts in $HOME is either a symlink it made or a file it generated, and the two
# are recognised in completely different ways: a link by where it points, a
# generated file by name and by the header written into it. Merging them into
# one "delete this path" helper would mean the caller supplies the only
# safeguard, which is the arrangement that eventually deletes something.

# fs_unlink DST -- remove a symlink this repo created.
#
# Narrower than `rm` by design: a real file at a path a module once owned is
# left where it is. Rule 2 above says an apply never destroys a real file, and
# an uninstall that did would make that promise good only until the next
# command.
fs_unlink() {
  local dst=$1
  [[ -L $dst ]] || return 0
  info "unlink  ${dst/#$HOME/\~}"
  [[ $DOT_DRY_RUN == 1 ]] || rm -f "$dst"
}

# fs_discard DST -- remove a real file this repo generated.
#
# ~/.local/bin/dot and ~/.config/git/config.local are written, not linked --
# their contents depend on this machine -- so no symlink scan can find them.
# Callers must establish ownership first: both carry a line naming the repo,
# and both are checked before they get here.
fs_discard() {
  local dst=$1
  [[ -f $dst ]] || return 0
  info "remove  ${dst/#$HOME/\~}"
  [[ $DOT_DRY_RUN == 1 ]] || rm -f "$dst"
}

# fs_check_tree DIR -- read-only drift report for one module.
# Returns 1 if anything is out of place. Never modifies the filesystem.
fs_check_tree() {
  local src dst rel state drift=0
  while IFS=$'\t' read -r src dst; do
    state=$(fs_classify "$src" "$dst")
    rel=${dst#"$HOME"/}
    case $state in
      ok) ;;
      missing) warn "not linked      ~/$rel" ;;
      wrong-target) warn "wrong target    ~/$rel" ;;
      clobbered)
        # These labels are a 16-character column, which "real directory" fills
        # exactly -- that is why the column widened rather than the word
        # shrinking to "dir".
        if [[ -d $dst ]]; then
          warn "real directory  ~/$rel"
        else
          warn "real file       ~/$rel"
        fi
        ;;
      broken) warn "broken link     ~/$rel" ;;
    esac
    [[ $state == ok ]] || drift=1
  done < <(fs_pairs "$1")
  return $drift
}

# fs_report -- the closing summary of a `dot apply`.
fs_report() {
  local parts=() summary
  ((DOT_N_LINKED)) && parts+=("$DOT_N_LINKED linked")
  ((DOT_N_RELINKED)) && parts+=("$DOT_N_RELINKED relinked")
  ((DOT_N_BACKED_UP)) && parts+=("$DOT_N_BACKED_UP backed up")
  ((DOT_N_UNCHANGED)) && parts+=("$DOT_N_UNCHANGED unchanged")

  if ((${#parts[@]} == 0)); then
    say "No files to link."
  else
    # Joined with printf rather than IFS + "${parts[*]}": that form uses only
    # the FIRST character of IFS, so `IFS=', '` produced "3 linked,3 backed up".
    summary=$(printf ', %s' "${parts[@]}")
    say "${summary:2}"
  fi

  # The path, not a variable this process may never have set -- the point of
  # the change is that a hook's backups get reported by the driver too.
  if fs_backup_used; then
    dim "Replaced files were moved to $DOT_STATE/backups/$DOT_RUN_ID"
  fi
}

# fs_repo_links -- every symlink under $HOME that points into this repo.
#
# This is why v2 needs no "what did I apply last time" state file: the
# filesystem already records every link, so the answer is derivable. Doctor
# wants the ones nobody claims and an uninstall wants all of them, so the walk
# lives here and fs_orphans is a filter over it -- neither verb gets its own
# idea of which links belong to this repo.
#
# The filter on "points into $DOT_ROOT" is what keeps this safe to delete from.
# A link you made yourself, to somewhere else, is not this repo's to remove --
# which is also why containers/remove.sh has to name its docker plugin links:
# those point into Homebrew's prefix, not into here.
fs_repo_links() {
  # A hash map because its job is to collapse duplicates -- the same directory
  # is named by every file a module puts in it.
  local -A roots=()
  local dir src dst link target
  local -a scan

  # Where to look comes from EVERY module, not just the enabled ones. It used
  # to come from the enabled set, which made the main case invisible: disabling
  # a module dropped its directory from the scan, so the links it left behind
  # were never looked at.
  #
  # `while read`, not `for dir in $(...)`: the unquoted form word-splits, so a
  # repo cloned into a path with a space in it scanned the wrong directories.
  while IFS= read -r dir; do
    while IFS=$'\t' read -r src dst; do
      roots[$(dirname "$dst")]=1
    done < <(fs_pairs "$dir")
  done < <(
    modules_all_dirs
    printf '%s\n' "$DOT_ROOT/core"
  )

  ((${#roots[@]})) || return 0

  # Sorted so the report reads the same way twice; a hash map has no order.
  mapfile -t scan < <(printf '%s\n' "${!roots[@]}" | sort)

  # -maxdepth 1 keeps this bounded to directories some module actually
  # declares, so it never walks the whole of $HOME.
  for dir in "${scan[@]}"; do
    [[ -d $dir ]] || continue
    while IFS= read -r -d '' link; do
      target=$(readlink "$link") || continue
      [[ $target == "$DOT_ROOT"/* ]] || continue
      printf '%s\n' "$link"
    done < <(find "$dir" -maxdepth 1 -type l -print0 2>/dev/null)
  done
}

# fs_orphans -- the repo's links that no ENABLED module claims. Left behind by
# disabling a module or by deleting a file from the repo.
#
# Only enabled modules claim, and that half must stay narrow: the scan above
# deliberately looks in every module's directories, so letting a disabled
# module claim its files back would hide every orphan the wide scan exposes.
fs_orphans() {
  # A map so that "did anyone claim this link?" is one lookup, not a scan.
  local -A claimed=()
  local dir src dst link

  while IFS= read -r dir; do
    while IFS=$'\t' read -r src dst; do
      claimed[$dst]=1
    done < <(fs_pairs "$dir")
  done < <(
    modules_enabled_dirs
    printf '%s\n' "$DOT_ROOT/core"
  )

  while IFS= read -r link; do
    [[ -n ${claimed[$link]:-} ]] || printf '%s\n' "$link"
  done < <(fs_repo_links)
}
