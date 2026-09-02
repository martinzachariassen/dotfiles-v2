# `modules/`

**The directory listing is the registry.** No central manifest; adding a module
means creating a directory. `tests/contract.bats` walks the same glob the
driver walks, which is what makes that safe.

```
modules/<name>/
  module.toml      required -- exactly one field: description
  Brewfile         optional -- phase 2 packages
  home/            optional -- mirrored into $HOME, leaves linked
  apply.sh         optional hook
  doctor.sh        optional hook
  remove.sh        optional hook
```

Lowercase names matching the directory. **150 lines of shell per directory.** A
module that wants more is two modules, or one whose logic belongs in the engine
-- where something else must go to make room.

`remove.sh` exists for one gap: the uninstall sweep only sees links pointing
into `$DOT_ROOT`. Links to targets outside the repo (`containers`) and
generated real files (`git`) must clean up after themselves. A fourth hook
needs a gap that specific.

## Writing a hook

Hooks are **executed, not sourced** -- `bash modules/git/doctor.sh` is exactly
what the driver does, and nothing leaks back except an exit status.

```sh
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"
```

- Read settings through `module_setting` (dasel parses `-` as subtraction).
- **Validate values yourself.** `defaults write ... -int big` exits 0 and
  stores 0. So do dasel and git config: they accept anything.
- Prefer `fail` over `die` for one bad setting, so the rest of the hook still
  runs. `fail` does not exit; it bumps a tally.
- Honour `DOT_DRY_RUN`, or a preview becomes a run.
- Warn-only hooks exit `DOT_STATUS_WARN`. Never `|| true`.

## doctor.sh

Only check what fails **silently**, and never write anything -- `dot doctor` is
the read-only verb, and `contract.bats` snapshots `$HOME` around every hook to
prove it (`colima status` creates `~/.colima` just by being asked).

## remove.sh

Use `fs_unlink` (`-L`) and `fs_discard` (`-f`), never `rm`. Report what cannot
be reversed: `macos-defaults` cannot restore your old values, because apply
never read them and there is no state file. If that trade is ever made, make it
deliberately.

## Checkpoint at ~8 modules

Modules run alphabetically. If one ever needs to run after another, that is a
dependency and needs a real answer -- not an `order` integer.
