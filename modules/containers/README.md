# containers

Docker on this machine is [colima](https://github.com/abiosoft/colima): a Linux
VM running dockerd, driven by the ordinary `docker` CLI. Docker Desktop is not
installed and is not wanted -- it ships a GUI, a licence, and a privileged
helper for a daemon this replaces in one command.

```sh
colima start          # first run downloads the VM image; takes a few minutes
docker ps             # colima registered the docker context for you
colima stop           # reclaims the RAM
```

The module installs the packages and links Homebrew's compose and buildx
plugins into `~/.docker/cli-plugins`, which is the only place the docker CLI
looks for them.

## Not automatic

**Nothing starts the VM at login.** The previous dotfiles registered a launchd
agent for it, which was ~80 lines of `launchctl bootout`/`bootstrap` with a
transient failure mode, in exchange for saving one command on the mornings you
actually use Docker. `dot doctor` reports a stopped VM instead.

If you want it on a given machine, Homebrew already ships the service
definition, so there is no plist to write:

```sh
brew services start colima
```

That line stays out of `apply.sh` on purpose. Installing colima makes it
available; starting it at login changes how the machine behaves all day, for a
VM that holds its CPUs and RAM whether or not you open Docker. It is a
per-machine choice, and turning it on makes `dot doctor`'s "not running"
warning wrong -- a stopped VM would be a real failure by then, not the normal
state.

**The VM's shape stays a per-machine command.** `colima start --cpu 6
--memory 12` is remembered for that instance and takes effect on the next
start, so a machine that needs more says so once, there. The template below
sets what a machine's *first* boot gets, and nothing after it.

## The one thing that is configured here

`home/.colima/_templates/default.yaml` is linked into place so that the first
`colima start` on a machine runs with `sshConfig: false`.

Left at colima's default of `true`, every start prepends an `Include` line to
`~/.ssh/config` -- which on this machine is a symlink into this repo. The write
follows the link and lands in `modules/ssh/home/.ssh/config`: an absolute
`/Users/<name>/` path committed to a public repo, above the `config.local`
`Include` that file documents as having to come first. `ssh colima` still works;
the generated config lives in `~/.colima/ssh_config` either way, and you can
`Include` it from `~/.ssh/config.local` if you want it.

Three things about that file:

- **It only reaches instances that do not exist yet.** Once
  `~/.colima/<profile>/colima.yaml` is written, the template is never read
  again. On a machine that already started colima, fix the profile instead:
  `colima stop && colima start --ssh-config=false`. `dot doctor` warns when a
  profile on disk still has it on.
- **The other keys in it are colima's defaults, restated, and have to stay.**
  The template replaces the command's flag defaults rather than merging over
  them, so a file containing only `sshConfig` starts a VM with `cpu 0` and
  `disk 0`. The file says which keys and why.
- **`cpu: 4` and `memory: 8` are the deliberate exception.** Since the keys
  have to be in the file regardless, stating them costs nothing, and colima's
  stock 2 GiB is enough to run a container but not to build one -- the failure
  is a buildkit step OOM-killed inside the VM, surfacing as a build error that
  never mentions memory. Raise or lower it per machine with the command above.
