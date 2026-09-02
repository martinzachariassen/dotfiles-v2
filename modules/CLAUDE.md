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

## Two shapes, one contract

The driver knows only "a directory that can be enabled". To a reader the
directories are two populations, and mixing them up is what makes `modules/`
feel vague:

- **Tool modules** manage a tool's configuration -- `home/`, hooks, or both.
  Enabling one hands that tool to the repo.
- **Package sets** are a Brewfile and nothing else: `apps`, `dev-cli`. Enabling
  one installs software and changes no settings. Their `description` says
  `Packages:` so the wizard and `dot doctor` say which you picked.

Nothing enforces this and nothing should -- a flag or a second registry would
buy a distinction the driver has no use for. It already prints `packages only`
for the second shape (`lib/modules.sh`), derived from the absence of `home/` and
`apply.sh` rather than recorded anywhere.

**A module that owns a tool's config owns its `Brewfile` line.** That is what
keeps the two populations from bleeding: the moment something in a package set
grows a config file, it leaves for its own module and takes its package with
it, or enabling that module gets you half a tool. Repeating a `brew` line
across two modules is fine -- `brew bundle` is idempotent, and it is the only
way to say "I need this too" where modules run alphabetically and cannot depend
on each other.

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
