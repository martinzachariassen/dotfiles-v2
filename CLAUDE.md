# Working in this repo

Read this before adding anything. Most of it is a rule plus the specific v1
failure that produced it -- this repo is a rewrite, and the rules are the part
worth keeping.

## Language

All code, comments, commit messages and docs are in **English**.

## The size budget

Two caps, enforced by `make size` in CI:

- **The engine -- `install.sh`, `uninstall.sh`, `bin/dot`, `lib/`, `core/` --
  is capped at 2500 lines.** This is the part v1 rotted in, so growth here has
  to be a deliberate act rather than a drift.
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

**The engine cap moved from 1300 to 2500 once, and the reason matters more
than the number.** 1300 was derived from a premise -- "the engine is finished:
linking a file, reading a config and running a hook do not get harder as you
own more things" -- and the premise was retired on purpose, because there is
more the engine is meant to do. A cap follows the scope it was derived from.
It does not follow the pressure of the change in front of you: "I need 14 more
lines" is the one argument that never works, and the fix for it is still to
cut. If the engine reaches 2500, the question to answer first is which premise
changed, not which number is convenient.

**The line count was never the real constraint anyway.** What keeps the engine
from becoming v1 is the shape rules below -- 7 files in `lib/`, 1 field in
`module.toml`, 60 lines of wizard, 3 verbs in `bin/dot`. v1's `core/` was 1324
lines, comfortably inside 2500, and it was already unmaintainable: 13 files,
two registries and a second ordering axis. Those limits are load-bearing in a
way a line count is not.

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

**Uninstalling is `uninstall.sh` at the root, not a fourth verb.** `bin/dot` is
capped at three, and the cap held: the most destructive thing the repo can do
also does not belong behind the command you type every day. The real argument
for the root, though, is that the last two steps remove the ground the script
stands on -- Homebrew owns the bash 5 interpreting it, and `$DOT_ROOT` holds
the file. So it ends the way `install.sh` does, with an `exec`: `install.sh`
execs *into* the repo, `uninstall.sh` execs *out* of it, into a throwaway
script under `/tmp` that depends on neither. That turns "when does bash re-read
a deleted script" into a question nobody has to answer.

**An unquotable checkout path is refused once, not escaped three times.** Three
places bake `$DOT_ROOT` into a script: `core/apply.sh` writes the shim,
`uninstall.sh` writes the throwaway it execs into, and both readers `grep -F`
for the shim's exact `DOT_ROOT="<path>"` line. A `"` in the path makes that
throwaway a syntax error -- so you type `remove`, and Homebrew and the repo are
both still there afterwards with nothing said about why -- and a backtick or
`$( )` is not a broken string but a command the generated script runs.
Escaping at each site would be one rule in three copies that have to agree
forever, and the greps would have to learn the escaped form too. `lib/dot.sh`
rejects the path instead, right after deriving it and before the first
`source`. Spaces and non-ASCII stay legal, and that half is load-bearing: every
use is already quoted, and quoting is exactly what those four characters
defeat. A guard that refuses paths people really have is a guard that gets
deleted.

**A destructive summary states counts, not categories.** The confirmation line
read "Homebrew and every package it installed" -- true, and read by everyone as
"the packages this repo installed", when the answer is every package on the
machine. It now counts: "all 113 packages it manages", then warns that 74 of
them are named by no Brewfile here. This is doctor's Result line again, one
verb over: a summary that lets you misread it is the bug, not the prose around
it. Anything irreversible gets a number.

**An uninstall is derived, not recorded.** No state file, for the same reason
`fs_orphans` needs none: the filesystem already records every link. An
uninstall is the orphan scan with nothing enabled, so every link into the repo
is unclaimed by definition -- which is why `fs_repo_links` is the shared walk
and `fs_orphans` is now a filter over it. The two verbs must never develop
separate ideas of which links belong to this repo.

**`remove.sh` is the third hook, and it exists for one specific gap.** The
sweep filters on "points into `$DOT_ROOT`", and widening that filter would mean
deleting links the repo never made. So the two things it structurally cannot
see get named by their own module: `containers` links Homebrew's docker
plugins, whose targets are outside the repo, and `git` writes a real file. A
fourth hook needs a gap that specific.

**An apply never deletes -- and neither does an uninstall, quite.** Real files
in the way are moved to the backup tree.
Orphaned links are reported by `dot doctor`, never removed. The orphan scan
takes its directories from **every** module in the repo, not the enabled ones:
a link left behind by a module you just disabled is the main thing it looks
for, so deriving the scan from the enabled set hid exactly the case it exists
to catch. Only enabled modules *claim* files -- that half must stay narrow, or
widening the scan would hide every orphan it just exposed.

`uninstall.sh` keeps the promise rather than voiding it one command later: it
removes symlinks and two provably-generated files, never a real file, and it
leaves the backup tree standing with a warning. Those backups are the only copy
of what an apply moved aside. `fs_unlink` tests for `-L` and `fs_discard` for
`-f` for exactly this reason -- the guard lives in the helper, not in each
caller, because "the caller supplies the only safeguard" is the arrangement
that eventually deletes something.

**Spend Homebrew's knowledge before destroying it.** Homebrew's uninstaller
deletes the prefix and nothing outside it, and two things it installs live
outside: a cask's `.app`, which it *moves* into `/Applications` so it no longer
resolves back into the Cellar, and a service's launchd plist in
`~/Library/LaunchAgents`. Left alone, a full reset strands every GUI app on the
machine -- still installed, with nothing left that can update or remove it,
which is the single worst state an uninstall can leave behind. The fix is
ordering, not machinery: `uninstall.sh` stops services and then
`brew uninstall --cask --zap` every cask *by name*, while `brew` still works.
A cask that fails to uninstall is a `fail`, so the `DOT_FAILURES` guard stops
the run before the handoff -- tearing out the only tool that could remove an
app you just failed to remove would manufacture the exact leftover the step
exists to prevent. The corollary is a counting rule: `brew_headcount` is
formulae-only on both sides, because the casks were already itemised by name
and a preview that claims the same 28 applications twice is a preview nobody
finishes reading.

**macOS defaults are one-way, and that is written down rather than hidden.**
`apply` never read the old values, so nothing anywhere has them, and `defaults
delete` restores Apple's factory setting rather than yours. Making it
reversible means recording state at apply time -- a state file, which is the
thing this repo does not have. `modules/macos-defaults/remove.sh` reports the
domains and says why. If that trade is ever made, make it deliberately.

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
| `module.toml` | 1 field | Field creep is the path back to `feature.sh`. A second needs a written justification and an edit to `contract.bats`. `default` went with the `custom` profile that read it; `order` went once every module had settled on the same value; `sudo` went once every module had settled on `false` -- a module that needs root calls `sudo` in its own `apply.sh`, which is what this checkpoint always said the fallback was. |
| `lib/wizard.sh` | 60 lines | Where the 587-line monster regrows. If it needs a loop over a question schema, stop. |
| `bin/dot` | 3 verbs, hardcoded `case` | A verb table grew to 84 lines with five drifting consumers. Modules ship scripts in `home/.local/bin/` instead; `uninstall.sh` sits at the root. |
| module hooks | 3 names: `apply.sh`, `doctor.sh`, `remove.sh` | Closed set, enforced by `contract.bats`. `remove.sh` earned its place on a gap the generic sweep cannot close, not on symmetry. |

## Review checkpoints

Revisit these once there are ~8 modules:

- **Alphabetical module order.** `modules_enabled` just sorts by name. If a
  module ever genuinely needs to run after another one, that is a dependency,
  and it needs a real answer -- not the `order = 50` integer that used to be
  here and that every module set to a number nobody chose.

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

**A subshell cannot memoise anything, and neither can a process.** Every caller
of `modules_enabled` reads it as `< <(modules_enabled)`, so a cache variable set
inside is discarded with the subshell. Things that must happen once per run --
warnings, validation -- belong at the call site in `bin/dot`, not in the
function being called.

`fs_backup_dir` is the worked example, and it took two attempts because there
are two boundaries, not one. Called as `$(fs_backup_dir)` the memo died in the
subshell: every collision re-ran `date`, one apply scattered its backups across
a directory per second, and the line saying where they had gone vanished from
the report. Assigning to a global fixed the subshell and not the **process** --
a hook is its own bash process, so a file `containers/apply.sh` moved aside went
into a directory the driver had never heard of and the summary reported no
backups at all. The answer was to stop remembering and start deriving:
`DOT_RUN_ID` is set once in `lib/dot.sh` and **exported**, so every process in
the run computes the same path without anyone having to share anything. When
something must be agreed on across a process boundary, an inherited input beats
a remembered value.

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

**dasel does not validate, and that is the most dangerous fact in this file.**
On a malformed line it stops parsing, keeps everything it read up to there, and
**exits 0**. So one missing comma in `enabled = [ "git", "zsh" "macos-defaults" ]`
deletes the whole `[modules]` table from the parsed document while every key
above it still answers. The old health check asked for `schema`, which the
generator writes *above* all user-editable content, so it could never fail on a
hand-edit -- and hand-editing is the supported workflow.

What that costs is not a wrong value. With no enabled modules every link into
the repo is unclaimed by definition, so `dot doctor` reported a working setup as
orphaned and closed with `Remove with: rm <path>`. A typo made the health check
tell you to delete your dotfiles.

`cfg_parse_problems` is the answer, and it is two checks because there is no
TOML parser here to be the one check: every `[table]` the file declares must be
visible in `keys()`, and `modules.enabled` must be *readable* -- which is not
the same as non-empty, since `enabled = []` is exactly what the `none` profile
writes. That second check is the whole difference between "nothing is enabled"
and "nothing could be read". `dot apply` refuses; `dot doctor` reports. The
residual is stated in the code: a typo inside the **last** table drops only
that table's remaining scalars, and closing it needs a real parser.

The corollary is that **nothing user-supplied gets interpolated into a
structured file unescaped**. `config_generate` had `printf 'name  = "%s"'`, and
the wizard offers your global git identity as the default -- so `Martin "Zach" Z`
wrote a config that truncated at the stray quote, on a first run, with nothing
typed wrong. `modules/git/apply.sh` had the same shape into git's config
language, where `#` starts a comment: `name = Martin # 1` read back as `Martin`.
Both quote through a helper now.

`defaults` is the same trap one tool over, and it does not even need a quote:
`defaults write com.apple.dock tilesize -int big` exits 0 and stores **0**, so
`dock_tilesize = "big"` gave you a Dock whose icons have no width and no message
anywhere. `macos-defaults/apply.sh` checks the value itself and refuses it with
a `fail` rather than a `die`, so one bad field does not also cost you the Finder
and keyboard settings written below it. What dasel, git-config and `defaults`
have in common is the rule: when you shell out to a tool that will accept
anything you hand it, the validation has to live on this side of the call.

**dasel parses `-` as subtraction.** `settings.macos-defaults.dock` fails with
a type error, and neither `"` nor `'` quoting helps -- only bracket syntax,
`settings["macos-defaults"].dock`. Always go through `module_setting`; there is
a test pinning this. Note that `cfg_parse_problems` only ever *compares* table
names and never builds a selector from one, which is what keeps this problem
out of it.

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

**A check that finds something must reach `DOT_FAILURES`.** `module_doctor`
counts its own failures rather than returning a status, because the `|| true`
that used to be at its call site in `bin/dot` swallowed both a drifted file
tree and a failing hook: doctor listed the unlinked files, then printed
"Everything looks right" and exited 0. A health check that is wrong in that
direction is worse than no health check, and `|| true` on anything a doctor
calls is the shape the bug takes. Hook failures do not cross the process
boundary on their own -- a hook runs in its own bash process, so the driver
sees an exit status and has to convert it.

**Warnings are counted, and a summary line may not contradict them.** `warn`
bumps `DOT_WARNINGS` the way `fail` bumps `DOT_FAILURES`, and `dot doctor`'s
Result line has three branches, not two: problems, warnings, clean. It used to
have two, so a stopped colima and three orphaned links were followed by
"Everything looks right." -- which is how a report teaches you to skip it.
Warnings still do not change the exit status; `dot doctor && ...` keeps
working.

**A warning inside a hook needs a number to travel on.** A hook that only
warned is neither 0 nor 1, so it exits `DOT_STATUS_WARN` and its driver folds
that back in with `fold_status`. Before that existed, both readings of a
non-zero status were in the tree and both were wrong: doctor's `|| true` threw
the warning away, and apply's `if ! module_run_hook` turned it into a crash --
`git/apply.sh` warns about an empty `user.name`, and that was reported as
"git: apply.sh failed". `bin/dot` clears `__DOT_EXIT_WARN` for itself, because
it is nobody's hook.

**That number is 3, and it was 2, and the move is the point.** bash exits 2 on
a **syntax error** -- a hook with a typo in it, which executed nothing -- so
every driver in the repo read a script that never ran as "finished, with
something worth mentioning". The worst site was `module_remove`: `uninstall.sh`
refuses to hand off to the irreversible half while `DOT_FAILURES` is non-zero,
and a warning does not bump it, so a mistyped `remove.sh` let the run go on to
zap every cask, uninstall Homebrew and delete the repo with that module's
cleanup never having happened -- invisibly, because `macos-defaults/remove.sh`
exits warn on purpose and warnings during an uninstall look routine. Any number
can collide with whatever a hook's last command returned; the rule is that it
must not collide with the **interpreter**, which owns 0, 1, 2, 126, 127 and
128+n. There is a test asserting the property rather than the number.

## Before committing

```sh
make check
```

shellcheck, shfmt, bats and the size budget. The `Makefile` is the only copy of
those commands -- CI runs the same target. Do not inline them anywhere else;
there were three copies before, and they had already drifted.

## What comments are for

Comments here explain **why this decision**, not what bash syntax means. The
test is whether the line would survive being read by someone who already knows
bash: a comment that narrates the code is noise, a comment that records the bug
that produced the code is the only copy of that information.

Three things earn a comment:

- **A landmine** -- something that looks fine and is not. `cmd && printf` as the
  last statement in a loop, `colima status` creating `~/.colima`, a subshell
  that cannot memoise. Each of these has cost real time at least once.
- **An invariant** a future edit would break without noticing, ideally naming
  the other place that has to agree. Four files have to agree on bash 5; two
  verbs have to agree on which links belong to the repo.
- **A road not taken**, when the obvious alternative is wrong for a
  non-obvious reason -- a shim instead of a symlink, `rmdir` instead of
  `rm -rf`, casks removed before Homebrew.

There was a `docs/bash-guide.md` explaining every idiom used here in plain
English. It was deleted: a second file that has to stay in sync with the code
is the same failure as a second registry, and the idioms that actually cost
time are the ones above, which are documented where they bite. When an idiom
genuinely needs a word, give it one clause at the call site (`# < <(...) is a
subshell, so a variable set inside it does not survive`) rather than a pointer
somewhere else.
