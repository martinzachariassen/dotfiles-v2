# `lib/`

Sourced, never executed. **7 files, no subdirectories.**

| File | Owns |
|---|---|
| `dot.sh` | `$DOT_ROOT`, `DOT_RUN_ID`, bash-5 guard, ERR/EXIT traps |
| `ui.sh` | `say`/`ok`/`warn`/`fail`/`die`, `fold_status`, the tally |
| `config.sh` | reading and generating `config.toml` |
| `fs.sh` | linking, backups, orphan scan |
| `modules.sh` | discovery, enablement, hook running |
| `brew.sh` | Brewfile collection, `brew bundle` |
| `wizard.sh` | first-run picker -- **60 lines** |

## Config

**Written exactly once**, by `config_generate` at `dot config --init`. Every
TOML writer drops comments, so a hand-editable config only survives if nothing
rewrites it.

**dasel v3:** input on stdin (no `-f`), `-i` is input format, no in-place edit,
missing key exits 1. Everything read as `-o yaml` so `__cfg_unquote` has one
set of rules to undo: empty string comes back as `""`, anything with `: ` is
single-quoted.

**dasel does not validate.** On a malformed line it stops parsing, keeps what
it read, and **exits 0** -- one missing comma drops the whole `[modules]` table
while keys above it still answer. Empty enabled list means every link is
unclaimed, so doctor then tells you to delete your dotfiles.
`cfg_parse_problems` guards it with two checks: every declared `[table]` must
appear in `keys()`, and `modules.enabled` must be *readable* (not the same as
non-empty -- `enabled = []` is legal). `apply` refuses, `doctor` reports.
Residual: a typo in the last table drops only that table's remaining scalars.

**dasel reads `-` as subtraction.** Only bracket syntax works:
`settings["macos-defaults"].dock`. Always go through `module_setting`.
`cfg_parse_problems` compares table names and never builds a selector from one.

Interpolate user input through `__cfg_quote` only.

## Filesystem

- Directories are never symlinked, only traversed.
- `fs_repo_links` is the shared walk; `fs_orphans` filters it. Doctor and
  uninstall must never disagree on which links are ours.
- The orphan scan reads **all** modules; only enabled ones *claim* files.
  Narrow the first and you hide the disabled-module links it exists to find.
- `fs_unlink` tests `-L`, `fs_discard` tests `-f`. The guard lives in the
  helper, never the caller.

## Process and state

**Nothing can memoise.** Callers read `modules_enabled` via `< <(...)`, so a
cache set inside dies with the subshell; a hook is its own process, so globals
do not cross either. Once-per-run work belongs at the call site in `bin/dot`.
Things shared across processes are **exported inputs** (`DOT_RUN_ID`), not
remembered values.

**`lib/dot.sh` rejects a checkout path containing `"`, backtick or `$( )`**,
right after deriving `$DOT_ROOT`. Three places bake that path into generated
script, and two `grep -F` for it. Spaces and non-ASCII stay legal.

## Status

- `fail` bumps `DOT_FAILURES`, does not exit. The EXIT trap converts the tally.
- `warn` bumps `DOT_WARNINGS` and never changes the exit status.
- A hook that only warned exits `DOT_STATUS_WARN`; the driver folds it back
  with `fold_status`. It is **3, not 2** -- bash owns 2 for syntax errors, and
  a hook that never ran must not read as "finished with a note". A test asserts
  the property, not the number.
- The ERR trap prints one line and is guarded on `BASH_SUBSHELL == 0` (errtrace
  fires inside `$( )` where `toml_get` probes) and on no existing ERR trap
  (bats installs its own). Debug with `bash -x <hook>`.

## Wizard

60 lines because phase 1 installed `fzf`; the picker is one call. It offers the
profiles in `profiles.toml` plus `none`. Hand-picking modules means editing
`config.toml` -- there is no second route.
