# shellcheck shell=bash
#
# The symlink engine: the correctness core of this repo. Everything else can
# be rewritten on a whim; a bug in here loses files.
#
# Two rules govern the whole design:
#
#   1. Directories are NEVER symlinked, only traversed. If ~/.config were a
#      link into the repo, one module would own the entire tree and every
#      other tool's files would vanish from view. Only leaf files are linked;
#      parent directories are created as real directories.
#
#   2. A real file is never destroyed. It is MOVED to the backup tree, so
#      after a collision the file is in exactly one place -- not two, with no
#      way to tell which one you have been editing.

# Tallies for the end-of-run report.
DOT_N_LINKED=0
DOT_N_RELINKED=0
DOT_N_BACKED_UP=0
DOT_N_UNCHANGED=0
# Read by uninstall.sh rather than by fs_report: an apply removes nothing, so
# this line is always 0 in the report that fs_report prints.
DOT_N_REMOVED=0

# Set lazily on the first collision so a clean run leaves no empty directory
# behind. One directory per `dot apply` invocation.
__DOT_BACKUP_DIR=''

# Point __DOT_BACKUP_DIR at this run's backup directory, creating it on first
# use. Callers read the variable; this prints nothing on purpose.
#
# Never call it as `$(fs_backup_dir)`: a command substitution is a subshell, so
# the memoised assignment dies with it (see docs/bash-guide.md). Written that
# way, every collision re-ran `date` -- scattering one run's backups over
# several directories -- and fs_report lost the line saying where they went.
fs_backup_dir() {
  if [[ -z $__DOT_BACKUP_DIR ]]; then
    __DOT_BACKUP_DIR="$DOT_STATE/backups/$(date +%Y%m%d-%H%M%S)"
    [[ $DOT_DRY_RUN == 1 ]] || mkdir -p "$__DOT_BACKUP_DIR"
  fi
}

# Whether anything was backed up this run (drives the closing hint).
fs_backup_used() { [[ -n $__DOT_BACKUP_DIR ]]; }

# fs_pairs DIR -- emit "src<TAB>dst" for every leaf file under DIR/home.
#
# The single place that knows how a module's home/ tree maps onto $HOME, so
# apply and doctor can never disagree about what is expected on disk.
# `-type f` excludes symlinks by definition; the contract test enforces that
# the repo contains none anyway.
fs_pairs() {
  local dir=$1 home="$1/home" src rel
  [[ -d $home ]] || return 0
  # -print0 and `read -d ''` separate paths with a zero byte instead of a
  # newline -- the one character a filename cannot contain. See
  # docs/bash-guide.md.
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
#
# Idempotent: an already-correct link prints nothing and touches nothing, so
# re-running `dot apply` on an unchanged machine is silent.
fs_link() {
  local src=$1 dst=$2 rel=${2#"$HOME"/} state backup

  state=$(fs_classify "$src" "$dst")

  # Already correct: the common case on a re-run, and the only one that both
  # prints nothing and returns early.
  if [[ $state == ok ]]; then
    DOT_N_UNCHANGED=$((DOT_N_UNCHANGED + 1))
    return 0
  fi

  # Announce the intent first, so a dry run and a real run describe the change
  # in exactly the same words -- the report cannot drift from the action.
  case $state in
    missing) info "link    ~/$rel" ;;
    wrong-target | broken) info "relink  ~/$rel" ;;
    clobbered) info "backup  ~/$rel  (real file in the way)" ;;
  esac
  [[ $DOT_DRY_RUN == 1 ]] || {
    # A real file is moved aside; a symlink carries no data, so replacing one
    # needs no backup. Either way the link is created the same way afterwards.
    if [[ $state == clobbered ]]; then
      fs_backup_dir
      backup="$__DOT_BACKUP_DIR/$rel"
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
fs_link_tree() {
  local src dst
  while IFS=$'\t' read -r src dst; do
    fs_link "$src" "$dst"
  done < <(fs_pairs "$1")
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
# left exactly where it is. Rule 2 at the top of this file says an apply never
# destroys a real file, and an uninstall that did would make that promise good
# only until the next command.
fs_unlink() {
  local dst=$1
  [[ -L $dst ]] || return 0
  info "unlink  ${dst/#$HOME/\~}"
  [[ $DOT_DRY_RUN == 1 ]] || rm -f "$dst"
  DOT_N_REMOVED=$((DOT_N_REMOVED + 1))
}

# fs_discard DST -- remove a real file this repo generated.
#
# Generated files are the ones no symlink scan can find: ~/.local/bin/dot and
# ~/.config/git/config.local are written, not linked, because their contents
# depend on this machine. Callers must establish ownership first -- both of
# those carry a line naming the repo, and both are checked before they get
# here.
fs_discard() {
  local dst=$1
  [[ -f $dst ]] || return 0
  info "remove  ${dst/#$HOME/\~}"
  [[ $DOT_DRY_RUN == 1 ]] || rm -f "$dst"
  DOT_N_REMOVED=$((DOT_N_REMOVED + 1))
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
      missing) warn "not linked    ~/$rel" ;;
      wrong-target) warn "wrong target  ~/$rel" ;;
      clobbered) warn "real file     ~/$rel" ;;
      broken) warn "broken link   ~/$rel" ;;
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

  if fs_backup_used; then
    dim "Replaced files were moved to $__DOT_BACKUP_DIR"
  fi
}

# fs_repo_links -- every symlink under $HOME that points into this repo.
#
# This is why v2 needs no "what did I apply last time" state file: the
# filesystem already records every link, so the answer is derivable. Two
# callers read it, and between them they are the whole reason it is separate
# from fs_orphans -- doctor wants the ones nobody claims, an uninstall wants
# all of them, and neither should own the walk.
#
# The filter on "points into $DOT_ROOT" is what keeps this safe to delete from.
# A link you made yourself, to somewhere else, is not this repo's to remove --
# which is also why the containers module has to name its docker plugin links
# in its own remove.sh: those point into Homebrew's prefix, not into here.
fs_repo_links() {
  # `roots` is a hash map because its job is to collapse duplicates -- the same
  # directory is named by every file a module puts in it.
  local -A roots=()
  local dir src dst link target
  local -a scan

  # Where to look comes from EVERY module, not just the enabled ones. It used
  # to come from the enabled set, which made the main case invisible: disabling
  # a module dropped its directory from the scan, so the links it left behind
  # -- the main thing this is for -- were never looked at.
  #
  # `while read` over the module list, not `for dir in $(...)`: the unquoted
  # form word-splits, so a repo cloned into a path with a space in it scanned
  # the wrong directories.
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
