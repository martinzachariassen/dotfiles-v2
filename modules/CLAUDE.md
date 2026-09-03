# `modules/`

**The directory listing is the registry.** Adding a module is creating a
directory. `tests/contract.bats` walks the same glob the driver walks.

```
modules/<name>/
  module.toml      required -- exactly one field: description
  Brewfile         optional -- phase 2 packages
  home/            optional -- mirrored into $HOME, leaves linked
  apply.sh         optional hook
  doctor.sh        optional hook
  remove.sh        optional hook
  README.md        optional
```

Nothing else. Lowercase names matching the directory. **150 lines of shell per
directory.** Modules run alphabetically and cannot depend on each other.

## Two shapes, one contract

- **Tool modules** manage a tool's config: `home/`, hooks, or both.
- **Package sets** are a Brewfile and nothing else (`apps`, `dev-cli`). Their
  `description` starts with `Packages:`.

**A module that owns a tool's config owns its Brewfile line.** Repeating a
`brew` line across modules is fine (`brew bundle` is idempotent) and is the only
way to say "I need this too".

`remove.sh` exists for what the uninstall sweep cannot see: links whose target
is outside `$DOT_ROOT` (`containers`) and generated real files (`git`).

## Writing a hook

Hooks are **executed, not sourced**. `bash modules/git/doctor.sh` is exactly
what the driver does.

```sh
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"
```

- Read settings through `module_setting` only.
- **Validate values yourself.** `defaults`, dasel and git config accept
  anything and exit 0.
- `fail` over `die` for one bad setting, so the rest still runs.
- Honour `DOT_DRY_RUN`, or a preview becomes a run.
- Warn-only hooks exit `DOT_STATUS_WARN`. Never `|| true`.
- **`doctor.sh` never writes.** `contract.bats` snapshots `$HOME` around every
  one. `colima status` creates `~/.colima` just by being asked.
- **`remove.sh` uses `fs_unlink` and `fs_discard`, never `rm`.** Report what
  cannot be reversed (`macos-defaults`).
- A literal duplicated across hooks (`claude-code`'s allow/deny) needs a test
  that the copies agree.
