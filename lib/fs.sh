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

[[ -n ${__DOT_FS_SH:-} ]] && return 0
__DOT_FS_SH=1

# Tallies for the end-of-run report.
DOT_N_LINKED=0
DOT_N_RELINKED=0
DOT_N_BACKED_UP=0
DOT_N_UNCHANGED=0

# Set lazily on the first collision so a clean run leaves no empty directory
# behind. One directory per `dot apply` invocation.
__DOT_BACKUP_DIR=''

# Absolute path of this run's backup directory, creating it on first use.
fs_backup_dir() {
  if [[ -z $__DOT_BACKUP_DIR ]]; then
    __DOT_BACKUP_DIR="$DOT_STATE/backups/$(date +%Y%m%d-%H%M%S)"
    [[ $DOT_DRY_RUN == 1 ]] || mkdir -p "$__DOT_BACKUP_DIR"
  fi
  printf '%s\n' "$__DOT_BACKUP_DIR"
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
  while IFS= read -r -d '' src; do
    rel=${src#"$home"/}
    printf '%s\t%s\n' "$src" "$HOME/$rel"
  done < <(find "$home" -type f -print0 | sort -z)
  unset dir
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
  case $state in
    ok)
      DOT_N_UNCHANGED=$((DOT_N_UNCHANGED + 1))
      return 0
      ;;
    missing)
      if [[ $DOT_DRY_RUN == 1 ]]; then
        info "link    ~/$rel"
      else
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
      fi
      DOT_N_LINKED=$((DOT_N_LINKED + 1))
      ;;
    wrong-target | broken)
      # A symlink carries no data, so replacing one needs no backup.
      if [[ $DOT_DRY_RUN == 1 ]]; then
        info "relink  ~/$rel"
      else
        mkdir -p "$(dirname "$dst")"
        rm -f "$dst"
        ln -s "$src" "$dst"
      fi
      DOT_N_RELINKED=$((DOT_N_RELINKED + 1))
      ;;
    clobbered)
      # A real file: move it aside, never overwrite it.
      if [[ $DOT_DRY_RUN == 1 ]]; then
        info "backup  ~/$rel  (real file in the way)"
      else
        backup="$(fs_backup_dir)/$rel"
        mkdir -p "$(dirname "$backup")"
        mv "$dst" "$backup"
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
      fi
      DOT_N_BACKED_UP=$((DOT_N_BACKED_UP + 1))
      ;;
  esac
}

# fs_link_tree DIR -- link every file in DIR/home into $HOME.
fs_link_tree() {
  local src dst
  while IFS=$'\t' read -r src dst; do
    fs_link "$src" "$dst"
  done < <(fs_pairs "$1")
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
  local parts=()
  ((DOT_N_LINKED)) && parts+=("$DOT_N_LINKED linked")
  ((DOT_N_RELINKED)) && parts+=("$DOT_N_RELINKED relinked")
  ((DOT_N_BACKED_UP)) && parts+=("$DOT_N_BACKED_UP backed up")
  ((DOT_N_UNCHANGED)) && parts+=("$DOT_N_UNCHANGED unchanged")

  if [[ ${#parts[@]} -eq 0 ]]; then
    say "No files to link."
  else
    say "$(
      IFS=', '
      printf '%s' "${parts[*]}"
    )"
  fi

  if fs_backup_used; then
    dim "Replaced files were moved to $(fs_backup_dir)"
  fi
}

# fs_orphans -- symlinks under $HOME that point into the repo but that no
# enabled module claims. Left behind by disabling a module or by deleting a
# file from the repo.
#
# This is why v2 needs no "what did I apply last time" state file: the
# filesystem already records every link, so the answer is derivable. The scan
# is bounded to directories some module's home/ actually declares, which keeps
# it fast and stops it from walking all of $HOME.
fs_orphans() {
  local -a expected=() roots=()
  local dir src dst link target seen

  for dir in $(modules_enabled_dirs) "$DOT_ROOT/core"; do
    while IFS=$'\t' read -r src dst; do
      expected+=("$dst")
      roots+=("$(dirname "$dst")")
    done < <(fs_pairs "$dir")
  done

  [[ ${#roots[@]} -eq 0 ]] && return 0

  while IFS= read -r dir; do
    [[ -d $dir ]] || continue
    while IFS= read -r -d '' link; do
      target=$(readlink "$link") || continue
      [[ $target == "$DOT_ROOT"/* ]] || continue
      seen=0
      for dst in "${expected[@]}"; do
        [[ $link == "$dst" ]] && {
          seen=1
          break
        }
      done
      ((seen)) || printf '%s\n' "$link"
    done < <(find "$dir" -maxdepth 1 -type l -print0 2>/dev/null)
  done < <(printf '%s\n' "${roots[@]}" | sort -u)
}
