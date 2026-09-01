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

**The VM's shape is colima's business, not this repo's.** `colima start
--cpu 4 --memory 8` is remembered for that instance, so a config file here
would be a second place to say the same thing -- and it would only take effect
on `colima delete && colima start` anyway.
