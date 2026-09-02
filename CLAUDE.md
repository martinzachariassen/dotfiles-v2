# Working in this repo

Per-directory rules: [`lib/`](lib/CLAUDE.md) · [`core/`](core/CLAUDE.md) ·
[`bin/`](bin/CLAUDE.md) · [`modules/`](modules/CLAUDE.md) ·
[`tests/`](tests/CLAUDE.md)

All code, comments, commits and docs in **English**.

## Before committing

```sh
make check     # shellcheck, shfmt, bats, size budget
```

The `Makefile` is the only copy of those commands. Do not inline them elsewhere.

## Size budget

- Engine (`install.sh`, `uninstall.sh`, `bin/dot`, `lib/`, `core/`): **2500 lines**
- Each module directory: **150 lines** of shell. The sum is not capped.
- Tests: uncapped, excluded.

**Over budget means cutting something, never raising the number.** If you find
nothing to cut, that is the finding.

## Hard limits

- `lib/`: 7 files, no subdirectories
- `module.toml`: 1 field (`description`)
- `lib/wizard.sh`: 60 lines
- `bin/dot`: 3 verbs, hardcoded `case`
- Module hooks: `apply.sh`, `doctor.sh`, `remove.sh` -- closed set

All enforced by `make size` or `tests/contract.bats`. Changing one means
editing the test, deliberately.

## Root scripts

`install.sh` shares nothing -- plain `echo`, no library. It runs before the
repo exists.

`uninstall.sh` lives at the root, not behind a verb. Its last steps remove
Homebrew (which owns its bash) and `$DOT_ROOT` (which holds the file), so it
ends by `exec`ing a throwaway script in `/tmp`.

Rules it must keep:

- **Nothing deletes a real file.** Symlinks and provably-generated files only.
  The backup tree is left standing with a warning.
- **Derive, never record.** The uninstall is the orphan scan with nothing
  enabled. `fs_repo_links` is the shared walk for both verbs.
- **Casks before Homebrew.** `brew uninstall --cask --zap` by name while `brew`
  still works, or every GUI app is stranded with no tool left to remove it. A
  failed cask must abort the run before the handoff.
- **Irreversible summaries state counts, not categories** ("all 113 packages it
  manages", not "every package it installed").

## Repo-wide gotchas

**Bash 5. Four places must agree:** `install.sh` (`brew install bash`),
`core/Brewfile`, `bin/dot` (re-execs into `/opt/homebrew/bin/bash`),
`lib/dot.sh` (refuses to load below 5). CI installs it explicitly.

**Never end a loop with `cmd && printf`.** A false test on the last iteration
leaves the loop at status 1, which `set -e` turns into a dead `x=$(...)`. Use
`if`.

**Quote anything user-supplied before it reaches a structured file** -- TOML,
git config, `defaults`. These tools accept garbage and exit 0; validation lives
on this side of the call.

## Comments

Explain **why this decision**, not what bash does. Three things earn a comment:
a landmine that looks fine, an invariant a future edit would break (name the
other place that must agree), or a road not taken. Anything that narrates the
code is noise. No separate docs file -- it drifts.
