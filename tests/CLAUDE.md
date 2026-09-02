# `tests/`

bats, one file per unit. **Uncapped and excluded from the size budget**, so
"it would need a test" is never an argument against a change.

## Sandbox

`setup_sandbox` gives every test a throwaway `$HOME`. **Nothing may touch the
real home directory.**

Overriding `$HOME` is not enough: `XDG_CONFIG_HOME` and `XDG_STATE_HOME` are
pinned too, or a real apply runs `mkdir -p` outside the sandbox on a machine
that exports them. Counters and `DOT_RUN_ID` are reset per test. The library
loads from the real repo; only `$HOME` is fake.

Assert with `home_snapshot` diffs, not lists of paths you expect. Naming paths
only tests the ones you thought of.

## `contract.bats`

This is what makes the registry-free design safe. It walks the same glob as the
driver, so no module is exempt. Adding a `module.toml` field or a hook name
means editing this file -- that friction is the point.

## What to test

- **Properties, not constants** -- `DOT_STATUS_WARN` is asserted not to collide
  with any status the interpreter owns, not asserted to equal 3.
- Dry runs write nothing (snapshot, run, snapshot).
- Guards fire. That matters more than the happy path.
- Hostile input to anything reaching TOML, git config or `defaults`.

## bats notes

- bats installs its own ERR trap; `lib/dot.sh` checks for it before installing.
- End teardown with `return 0` -- a false last statement fails the teardown.
