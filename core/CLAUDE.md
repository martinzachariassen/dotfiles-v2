# `core/`

Phase 1. Same contract as any module (`Brewfile`, `apply.sh`, `doctor.sh`),
just first. Counts against the **engine** budget. Keep `apply.sh` near-empty --
core marks the phase boundary, it does not collect special cases.

## Phase order

`core/Brewfile` installs `dasel` and `fzf` before any module runs. **Nothing
that runs before `brew bundle --file core/Brewfile` may use a tool listed in
it.** That is what keeps the wizard at one `fzf` call.

Keep the file short: a package belongs here only if the machinery needs it, or
if you would be annoyed to find it missing anywhere. It also lists `bash` --
one of the four places that must agree on bash 5.

## The shim

`apply.sh` generates `~/.local/bin/dot` as a shim that exports `DOT_ROOT` and
execs the real path. Not a symlink: bash would set `BASH_SOURCE` to the link,
`bin/dot` would look for `lib/` beside `~/.local/bin`, and fixing that needs a
readlink loop duplicating `lib/dot.sh`. Generated rather than committed because
its content depends on the checkout path.

`core/doctor.sh` and `uninstall.sh` both `grep -F` its exact
`DOT_ROOT="<path>"` line -- hence the path guard in `lib/dot.sh`.

## Doctor checks

- A check earns its place only if the thing fails **silently**. "Is git
  installed" is not a check. "Is `~/.local/bin` on PATH" is.
- Everything found must reach `DOT_FAILURES`. Never `|| true` on anything a
  doctor calls.
- The Result line has three branches: problems, warnings, clean. A summary may
  not contradict the output above it.
- `dim`, not `warn`, for things true on every machine (uncommitted repo
  changes). A permanently yellow summary is the same bug as a permanently green
  one.
- Keep distinct causes distinct: shim missing vs. shim not executable.
  (`uninstall.sh` tests `-f`, not `-x` -- a shim that lost the bit is still
  ours to remove.)
