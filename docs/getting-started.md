# Getting started

How to use this repo on machines other than mine.

1. Fork/clone the repo to `~/nixos`.
2. Edit `variables.nix` — username, timezone/locale, cursor theme: what all your machines share.
3. Replace my machines in `hosts/` with yours ([machines.md](machines.md)): one folder per machine, named after its hostname, with a `variables.nix` saying whether it's a laptop, its CPU and GPUs, its disk, keyboard, monitors and the modules it leaves out. Start from a copy of whichever of mine is closest — or let `fresh-install.sh` do it: installing from scratch ([installing.md](installing.md)), it offers to set up "a new machine" from a copy of an existing one, and fills in its hardware, disk and `hardware-configuration.nix` itself.
4. Without `fresh-install.sh`, generate each machine's `hosts/<name>/hardware-configuration.nix` on it (`nixos-generate-config --show-hardware-config --no-filesystems`) — kernel modules and CPU microcode are never portable between machines, and the filesystems come from `modules/system/disko.nix` — and set its `disk` (`ls /dev/disk/by-id/`).
5. Leave out the modules tied to my hardware or apps, by adding them to your machines' `disabledModules` (or deleting their line from `modules/default.nix` / `modules/home/default.nix`, and the file if you like, to drop them everywhere):
   - `apps/amazfit.nix` — a specific smartwatch.
   - `virtualisation/windows-vm.nix` + `virtualisation/audio-routing.nix` — a Windows VM for one Windows-only voice changer, plus the virtual mic that brings its output back to the host. They go together.
   - `gaming/vr.nix` — a specific headset workflow.
   - `network/protonvpn.nix` needs your own WireGuard config in `secrets/secrets.yaml` (see [protonvpn.md](protonvpn.md)); its `apps` list and `network/tor.nix`'s launcher are personal choices too.
   - `system/secrets.nix` is encrypted for my age key. Either re-encrypt for your own ([secrets.md](secrets.md)) or leave it out together with `network/protonvpn.nix`.
6. Deploy ([deploying.md](deploying.md)), then work through [manual-setup.md](manual-setup.md) for what a rebuild can't do on its own.

Where a module depends on another one, `modules/default.nix` says so next to its line.
