# Working in this repo

Read this before adding anything. Most of it is a rule plus the specific v1
failure that produced it -- this repo is a rewrite, and the rules are the part
worth keeping.

## Language

All code, comments, commit messages and docs are in **English**.

## The size budget

Shipped shell code is capped at **1500 lines**; CI fails over it. Tests are
uncapped and excluded from the count.

v1 reached ~20,700 lines. Going over the cap means cutting something, not
raising the number. If you cannot find anything to cut, that is the finding.

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
| `module.toml` | 3 fields | Field creep is the path back to `feature.sh`. A fourth needs a written justification and an edit to `contract.bats`. `default` was the fourth; it went when the `custom` profile that read it went. |
| `lib/wizard.sh` | 60 lines | Where the 587-line monster regrows. If it needs a loop over a question schema, stop. |
| `bin/dot` | 3 verbs, hardcoded `case` | A verb table grew to 84 lines with five drifting consumers. Modules ship scripts in `home/.local/bin/` instead. |

## Review checkpoints

Revisit these once there are ~8 modules:

- **`order`** is a dependency system in disguise. If every module still says
  `50`, delete the field and sort by name.
- **`sudo`** buys one prompt instead of several. If the keepalive logic ever
  exceeds ~12 lines, cut the field and let `apply.sh` call `sudo` itself.
  (v1's `core/sudo.sh` reached 56 lines.)

## Gotchas that cost real time

**Target bash is 3.2.57.** macOS ships it and this repo installs no other, so
every `#!/usr/bin/env bash` resolves to it. No `declare -A` / `local -A`, no
`mapfile`/`readarray`, no `${x,,}`, no `BASHPID` (use `BASH_SUBSHELL`). A
`local -A` shipped once and failed only at runtime, on the one function with no
test; `tests/dot.bats` now greps for these constructs.

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
`lib/dot.sh` prints file, command and status -- nothing else. Both guards on it
are load-bearing: `BASH_SUBSHELL == 0` (errtrace fires it inside `$( )`, where
`toml_get` probes for missing keys, and a reporter that cries wolf gets
ignored) and `[[ -z $(trap -p ERR) ]]` (bats installs its own). It carries no
line number because bash 3.2 reports a function's definition line rather than
the failing one. For more, `bash -x <hook>` already exists; a `DOT_DEBUG`
variable with a custom `PS4` was tried and removed as not worth its weight.

**dasel v3 is not v2.** No `-f` flag (input comes on stdin), `-i` means input
format rather than in-place, and in-place editing was removed entirely.
`-o json` for scalars, `-o yaml` for arrays. A missing key exits 1.

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
bats tests/
shellcheck -x install.sh bin/dot lib/*.sh core/*.sh modules/*/apply.sh modules/*/doctor.sh
shfmt -d -i 2 -ci install.sh bin/dot lib/*.sh core/*.sh modules/*/*.sh tests/helper.bash
```
