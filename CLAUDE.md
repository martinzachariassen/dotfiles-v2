# Working in this repo

Read this before adding anything. Most of it is a rule plus the specific v1
failure that produced it -- this repo is a rewrite, and the rules are the part
worth keeping.

## Language

All code, comments, commit messages and docs are in **English**.

## The size budget

Two caps, enforced by `make size` in CI:

- **The engine -- `install.sh`, `bin/dot`, `lib/`, `core/` -- is capped at
  1300 lines.** This is the part v1 rotted in, and it is finished. Linking a
  file, reading a config and running a hook do not get harder as you own more
  things, so growth here has to be a deliberate act.
- **Each module's shell is capped at 150 lines**, counted per directory. The
  sum across modules is reported and *not* capped, and neither is the number of
  modules.

Tests are uncapped and excluded from both. The `Makefile` is not a `*.sh` file
and so is not counted either -- that is not a loophole to route logic through:
it holds the check commands and nothing else, because anything with logic in it
belongs in `lib/`, where shellcheck and the tests can see it.

**Why it is two numbers and not one.** It was a single 1500-line cap, which was
right about the danger and wrong about where it lives. At 1461 lines the engine
was 1240 of them and three modules were the other 221, so the next module with
hooks would have failed CI -- and the only way to pass would have been deleting
working engine code to make room for a Brewfile and a doctor. A rule that tells
you to break the tool because you bought a laptop accessory is a rule that will
be ignored the first time it fires, and a cap nobody respects is worse than no
cap. Splitting it keeps the pressure where the failure mode actually is.

**What has not changed:** going over means cutting something, or moving it to
where it belongs. It does not mean raising the number. If you cannot find
anything to cut, that is the finding. A module that wants more than 150 lines
is either two modules, or one whose logic belongs in the engine -- and if it
belongs in the engine, it has to fit in the engine's budget, where something
else will have to go.

## Load-bearing decisions

**Phase order is why this repo is small.** `core/Brewfile` (phase 1) installs
`dasel` and `fzf` before any module runs (phase 2). Nothing before that line
may use them. v1's wizard ran under `curl | bash` with no tools available and
grew to 587 lines of hand-rolled pickers; here the picker is one `fzf` call.

**The tool writes the config exactly once.** `config_generate` runs at
`dot config --init` and never again. Every TOML writer -- dasel included --
rebuilds the file from its parsed form and drops comments, so a commented,
hand-editable config is only possible if nothing rewrites it. In v1 the prompt
answers were the source and the config was derived, which forced `modules.sh`
to line-edit the generated TOML with grep+awk+`mv` and a BSD/GNU `stat` dance.

**The directory listing is the registry.** No central manifest of modules.
`tests/contract.bats` walks the same glob and enforces the contract, which is
what makes the absence of a list safe. v1 had two registries (`core/verbs.sh`
plus per-feature `feature.sh`) and a second ordering axis
(`FEATURE_DOCTOR_ORDER`) to keep in sync.

**`install.sh` shares nothing.** Plain `echo`, no library, no colour. It runs
before the repo exists. v1 duplicated ~100 lines of UI into its bootstrap for
this reason and the copies drifted; the fix is to have no UI worth sharing.

**An apply never deletes.** Real files in the way are moved to the backup tree.
Orphaned links are reported by `dot doctor`, never removed.

**There is one way to hand-pick modules: editing `config.toml`.** The wizard
offers the profiles in `profiles.toml` plus `none`, which writes an empty list
and gets out of the way. A "custom" profile was a second route to the same
place. Because hand-editing is expected, `dot apply` **validates** `enabled`
up front and refuses on an unknown name (`modules_require_known`); `dot doctor`
reports the same thing without dying, being the read-only verb.

**Directories are never symlinked, only traversed.** See `lib/fs.sh`.

## Hard limits

| Thing | Limit | Why |
|---|---|---|
| `lib/` | 7 files, no subdirectories | v1's `core/` was this shape at 13 files / 1324 lines. Pressure to add an eighth is a signal to delete something. |
| `module.toml` | 2 fields | Field creep is the path back to `feature.sh`. A third needs a written justification and an edit to `contract.bats`. `default` went with the `custom` profile that read it; `order` went once every module had settled on the same value. |
| `lib/wizard.sh` | 60 lines | Where the 587-line monster regrows. If it needs a loop over a question schema, stop. |
| `bin/dot` | 3 verbs, hardcoded `case` | A verb table grew to 84 lines with five drifting consumers. Modules ship scripts in `home/.local/bin/` instead. |

## Review checkpoints

Revisit these once there are ~8 modules:

- **Alphabetical module order.** `modules_enabled` just sorts by name. If a
  module ever genuinely needs to run after another one, that is a dependency,
  and it needs a real answer -- not the `order = 50` integer that used to be
  here and that every module set to a number nobody chose.
- **`sudo`** buys one prompt instead of several. If the keepalive logic ever
  exceeds ~12 lines, cut the field and let `apply.sh` call `sudo` itself.
  (v1's `core/sudo.sh` reached 56 lines.)

## Gotchas that cost real time

**Target bash is 5, and four places have to agree on that.** macOS ships 3.2.57
(2007) as `/bin/bash` and never updates it, so: `install.sh` runs
`brew install bash` before it hands off (phase 1 is too late -- `bin/dot` is
already running by then), `core/Brewfile` lists it so `brew bundle` keeps it,
`bin/dot` re-execs itself into `/opt/homebrew/bin/bash` if it started under an
older one, and `lib/dot.sh` refuses to load under one. CI installs it
explicitly, or the suite silently tests the wrong shell.

**`cmd && printf` as the last thing in a loop is a landmine.** A false test on
the final iteration leaves the loop at status 1. Under `set -e` that kills an
enclosing `x=$(...)`, and with `pipefail` it survives a `| sort` to reach the
caller. Use `if`. This bug has now appeared twice, in `lib/wizard.sh` and
`lib/modules.sh`.

**A subshell cannot memoise anything.** Every caller of `modules_enabled` reads
it as `< <(modules_enabled)`, so a cache variable set inside is discarded with
the subshell. Things that must happen once per run -- warnings, validation --
belong at the call site in `bin/dot`, not in the function being called.

**Failure reporting is one line, and stays one line.** The ERR trap in
`lib/dot.sh` prints file, line, command and status -- nothing else. Both guards
on it are load-bearing: `BASH_SUBSHELL == 0` (errtrace fires it inside `$( )`,
where `toml_get` probes for missing keys, and a reporter that cries wolf gets
ignored) and `[[ -z $(trap -p ERR) ]]` (bats installs its own). For more,
`bash -x <hook>` already exists; a `DOT_DEBUG` variable with a custom `PS4` was
tried and removed as not worth its weight.

**dasel v3 is not v2.** No `-f` flag (input comes on stdin), `-i` means input
format rather than in-place, and in-place editing was removed entirely. A
missing key exits 1. Everything is read as `-o yaml`, scalars included: one
output format means one set of quoting rules to undo, in `__cfg_unquote`. YAML
quotes a value only when it has to, so the two cases that matter are an empty
string (comes back as `""`) and anything containing `: ` (single-quoted).

**dasel parses `-` as subtraction.** `settings.macos-defaults.dock` fails with
a type error, and neither `"` nor `'` quoting helps -- only bracket syntax,
`settings["macos-defaults"].dock`. Always go through `module_setting`; there is
a test pinning this.

**Hooks are executed, not sourced.** `bash modules/git/doctor.sh` reproduces
exactly what `dot doctor` does. Process isolation is why no hook can leak a
variable into the driver.

**`fail` does not exit.** It bumps `DOT_FAILURES`; the EXIT trap in
`lib/dot.sh` turns a non-zero tally into a non-zero status, so a doctor run
reports every problem in one pass.

## Doctor checks

A check earns its place only if the thing it checks fails **silently**. "Is git
installed" is not a check -- you would notice. "Is `~/.local/bin` on PATH" is,
because the symptom is a command that mysteriously does not exist.

## Before committing

```sh
make check
```

shellcheck, shfmt, bats and the size budget. The `Makefile` is the only copy of
those commands -- CI runs the same target. Do not inline them anywhere else;
there were three copies before, and they had already drifted.

## Explaining bash

The repo owner is not a shell expert. `docs/bash-guide.md` explains every idiom
used here in plain English -- keep it current when introducing a new one, and
prefer a one-clause pointer at the call site
(`# < <(...) is a subshell; see docs/bash-guide.md`) over re-explaining the
idiom inline. Comments in the code are for **why this decision**, not for what
bash syntax means.
