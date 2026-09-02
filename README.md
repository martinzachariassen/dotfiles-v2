# dotfiles

macOS setup: Homebrew, packages, and config files. One command on a fresh Mac.

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles-v2/main/install.sh | bash
```

## What happens

| Phase | What runs | What it does |
|---|---|---|
| 0 | `install.sh` | Xcode Command Line Tools → Homebrew → clone → hand off |
| 1 | `core/Brewfile` | Packages every machine gets, including `dasel` and `fzf` |
| 2 | modules | Only what you pick: packages, config files, system settings |

The order is load-bearing. Phase 1 installs the tools phase 2 needs, which is
why the module picker can be one `fzf` call instead of a hand-rolled menu.

## Commands

```
dot apply              Install packages, link configs, run module hooks
dot apply --dry-run    Show every intended change, make none
dot config             Open the config file in $EDITOR
dot config --init      Create it for the first time (runs the picker)
dot doctor             Check this machine; read-only
```

Removing it all again is `uninstall.sh`, not a fourth verb — see
[Uninstalling](#uninstalling).

Re-running `dot apply` is safe and expected. It is also the update path:

```sh
git -C ~/Developer/personal/dotfiles-v2 pull && dot apply
```

## Configuration

`~/.config/dotfiles/config.toml` is the only source of truth. It is generated
**once**, by `dot config --init`, and belongs to you from that moment on --
nothing in the tool ever rewrites it. That is what keeps your comments intact,
and it is why turning a module on later is an edit rather than a wizard re-run:

```toml
[modules]
enabled = ["git", "zsh", "dev-cli"]

[settings.git]
signingkey = "ssh-ed25519 AAAA..."
```

Then `dot apply`.

`dot apply` validates `enabled` before it touches anything: a name with no
matching module stops the run and prints the list of real ones. Editing this
file by hand is a supported workflow, so a typo has to be an error -- the
alternative is a run that reports success having installed three modules out
of four.

### Profiles

`dot config --init` offers the profiles in `profiles.toml` as starting points
for the checklist, plus **`none`**. Picking `none` skips the picker and writes
an empty list, on the assumption you would rather fill it in yourself:

```toml
[modules]
enabled = []
```

There is no "custom" profile. Hand-assembling a module list is what the config
file is for, and two ways to do the same thing is one too many. Profiles are
only ever a first-run convenience -- `dot apply` never reads `profiles.toml`.

`profiles.toml` also carries a `[user]` table -- name, email, and the public
half of the SSH key that signs commits. **The wizard copies these into
`config.toml` and never asks for them**, because none of the three varies by
machine, and a prompt whose answer is always the same is ceremony. Change them
in `config.toml` afterwards; nothing reads `profiles.toml` again.

The signing key is safe in a public repo by construction: it is a *public* key,
the kind GitHub already serves at `github.com/<user>.keys`. The private half
never leaves 1Password.

## Modules

A module is a directory. **The directory listing is the registry** -- there is
no central list to update, because a central list is a thing that can disagree
with the filesystem. `tests/contract.bats` walks the same glob and enforces the
contract, which is what makes that safe.

```
modules/<name>/
├── module.toml     required   description (the only field)
├── Brewfile        optional   packages for this module
├── home/           optional   mirrors $HOME literally; leaf files are symlinked
├── apply.sh        optional   imperative, idempotent, run in its own process
├── doctor.sh       optional   read-only checks
├── remove.sh       optional   cleanup the uninstaller cannot derive
└── README.md       optional
```

Within a module the order is fixed: **Brewfile → links → apply.sh**, so
`apply.sh` can always assume its packages and config files are in place.

`modules/git` is config plus a small generator, `modules/zsh` is packages plus
config, `modules/macos-defaults` is purely imperative with no files at all, and
`modules/dev-cli` and `modules/apps` are nothing but a Brewfile. Between them
they show every shape the contract allows.

| Module | What it is |
|---|---|
| `git` | config, plus a generator for the machine-local identity |
| `ssh` | client config; keys stay in 1Password's agent |
| `zsh` | XDG layout, aliases, PATH, `$EDITOR`, starship, zellij |
| `dev-cli` | tools that are not baseline: gitleaks, lazygit, mise, claude-code |
| `apps` | GUI casks and fonts: 1Password, Raycast, VS Code, … |
| `containers` | [Docker via colima](modules/containers/README.md), no Docker Desktop |
| `macos-defaults` | Dock, Finder, keyboard, screenshots |

### Adding one

Create the directory, write the one line of `module.toml`, add whatever of the
optional files you need. Nothing else to register.

## How files get linked

Leaf files under a module's `home/` are **symlinked** into `$HOME` at the same
relative path, so editing `~/.config/git/config` edits the file in the repo.

Two rules matter:

- **Directories are never symlinked, only traversed.** If `~/.config` were a
  link into the repo, one module would own the whole tree and every other
  tool's files would vanish.
- **A real file in the way is moved, never overwritten** -- to
  `~/.local/state/dotfiles/backups/<timestamp>/`. After a collision it exists
  in exactly one place. A real *directory* where a file belongs is moved the
  same way, whole, and both `apply` and `doctor` say "directory" rather than
  "file" so the report matches the size of what just happened.

`dot doctor` reports drift in the words you will actually see -- `not linked`,
`wrong target`, `real file`, `real directory`, `broken link` -- plus any
orphaned links left behind by a disabled module. It reports them; it never
deletes anything in your home directory on its own.

## Uninstalling

```sh
bash uninstall.sh --dry-run    # print every intended change, make none
bash uninstall.sh              # do it
```

It is the counterpart to `install.sh` rather than a fourth `dot` verb: `bin/dot`
is capped at three, and the most destructive thing the repo can do does not
belong behind the command you type every day.

A full reset — links, generated files, config, Homebrew, and finally the
checkout. **Xcode Command Line Tools are left installed**, being macOS
developer plumbing rather than something this repo chose for you.

**Homebrew goes in its entirety, not just the packages this repo named.** Its
uninstaller removes the whole Cellar and Caskroom and keeps no record of who
asked for what, so a formula you installed by hand years ago goes with the
rest. The preview counts this out rather than describing it, because the
sentence version reads as "the packages this repo installed" and that is the
one misreading that matters:

```
Homebrew and the repo
  → uninstall Homebrew and all 85 formulae it manages
  ! 59 of those are named by no Brewfile here -- they go too
  → remove  /Users/you/Developer/personal/dotfiles-v2
```

**Casks are removed first, by name, while Homebrew still works.** They have to
be: Homebrew *moves* a cask's `.app` into `/Applications`, so it no longer
resolves back into the Cellar, and Homebrew's own uninstaller deletes the
prefix and nothing outside it. Left to itself it would strand every GUI app on
the machine — still installed, with nothing left that can update or remove
them. `brew services` leaks the same way, its launchd plists living outside the
prefix, so services are stopped before the apps go.

The ordering is the whole mechanism. Homebrew knows exactly what it put where,
right up until the step that destroys that knowledge, so the uninstall spends
that knowledge first. Each cask goes with `--zap`, which takes its application
support, preferences and caches too. If one of them *fails* to uninstall, that
is a `fail` like any other and the run stops before Homebrew — destroying the
only tool that could remove an app you just failed to remove is exactly the
leftover this step exists to prevent.

Casks are itemised by name in the preview and counted nowhere else; the
formula count above deliberately excludes them, so nothing is claimed twice.

Three things it will not do, and the reasons are the interesting part:

- **It never deletes your backup tree.** `~/.local/state/dotfiles/backups/`
  holds real files an earlier `apply` moved aside because they were in the way.
  Nothing else has a copy. "An apply never deletes" would be a promise good
  only until the next command if an uninstall threw them away.
- **It never deletes a real file** — only symlinks pointing into the repo, plus
  the two generated files it can prove it wrote (`~/.local/bin/dot` and
  `~/.config/git/config.local`, both of which carry the repo path or a
  generated-by header). `~/.local/state/dotfiles` itself is removed with
  `rmdir`, not `rm -rf`, so a file some other tool left there keeps the
  directory alive and gets reported instead of swept up.
- **It cannot undo macOS defaults.** `apply` never read the old values, so they
  exist nowhere; `defaults delete` would give you Apple's factory setting, not
  what you had. Making that reversible means recording state at apply time,
  which is a trade this repo has not made. It reports the domains instead.

The preview is not a summary written by hand — `--dry-run` is the real code
path with every mutating helper turned into a `printf`, so it cannot disagree
with the real run. The interactive run shows you that preview and then asks you
to type `remove`.

Most of the work is derived rather than recorded: an uninstall is the orphan
scan `dot doctor` already does, with nothing enabled, so every link into the
repo is unclaimed by definition. A module only needs a `remove.sh` for what
that scan structurally cannot see — `containers` links Homebrew's docker
plugins, whose targets are outside the repo, and `git` writes a real file.

## Templating

There isn't any, and that is a decision rather than an omission. Machine-local
values go through the tool's own include mechanism:

- git → `~/.config/git/config.local`, generated by `modules/git/apply.sh`
- zsh → `~/.config/zsh/local.zsh`, sourced if present, never tracked

If a generator ever needs a conditional, the conditional belongs in the tool's
own config language, not in bash.

## Development

```sh
make check     # shellcheck, shfmt, bats, and the size budget
```

That is the whole list, and it is exactly what CI runs -- the commands live in
the `Makefile` and nowhere else. Individually: `make lint`, `make fmt` (rewrites
files), `make test`, `make size`.

Shell code is capped, and CI enforces it:

| What | Cap | Why that shape |
|---|---|---|
| The engine: `install.sh`, `uninstall.sh`, `bin/dot`, `lib/`, `core/` | **2500 lines** | The part v1 rotted in. The number tracks what the engine is *for*, never what it happens to weigh this week. |
| Each module's shell scripts | **150 lines** | Enough for a module, not enough for a subsystem. |
| The number of modules, and their sum | uncapped | This is the axis the repo is supposed to grow along. |
| Tests | uncapped | `lib/fs.sh` moves files in `$HOME`, so it earns every test it has. |

Going over is a signal to cut something or move it, not to raise the number.
`make size` prints all of it.

### When something breaks

A crash prints one line -- the file, the line, the command and the status --
whether it happened in `dot` or inside a module hook run as its own process:

```
✗ modules/macos-defaults/apply.sh:24: defaults write com.apple.dock autohide -bool true (exit 1)
```

When one line is not enough, hooks are ordinary scripts:

```sh
bash -x modules/git/apply.sh
```

### Bash 5

The repo targets bash **5**. macOS still ships 3.2.57 from 2007 as `/bin/bash`
and never updates it, so `install.sh` runs `brew install bash` before anything
else in the repo starts, `core/Brewfile` keeps it managed afterwards, and
`bin/dot` re-execs itself into it if it somehow started under the old one.

That is one Homebrew package in exchange for associative arrays, `mapfile`, and
-- the reason it was worth doing -- correct line numbers in the crash report
above. Bash 3.2 names a function's *definition* line rather than the failing
one, so the number used to be left out entirely as worse than nothing.

## SSH and commit signing

There are no private keys on this machine. 1Password holds them and exposes an
agent socket; `ssh` asks that agent to sign, and the key itself never leaves the
vault. `modules/ssh` is the one line of config that points at it:

```
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

That path is the same on every Mac -- `2BUA8C4S2C` is AgileBits' Apple team ID,
not something per-user -- which is why it can be a tracked file rather than
something generated.

Commit signing rides on the same agent. `modules/git` writes `gpg.format = ssh`,
`commit.gpgsign = true` and your `signingkey` into `config.local` whenever the
key is set, so signing needs no second credential.

One step cannot be automated: **1Password -> Settings -> Developer -> "Use the
SSH agent"**. Until it is ticked the socket does not exist, and the failure
never mentions SSH config -- `git push` reports `Permission denied (publickey)`,
which reads as a key problem and sends you hunting through a key directory that
is empty on purpose. `modules/ssh/doctor.sh` checks the socket, so `dot doctor`
says so plainly instead.

The machine-local override file is `Include`d **first**, so anything in it wins
over the block above -- ssh takes the first value it obtains for each keyword.

## License

[MIT](LICENSE).
