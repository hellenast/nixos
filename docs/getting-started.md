# Getting started

How to use this repo on a machine other than mine.

1. Fork/clone the repo to `~/nixos`.
2. Regenerate `modules/system/hardware-configuration.nix` for your hardware (`nixos-generate-config`) — kernel modules and CPU microcode are never portable between machines. Drop the `fileSystems`/`swapDevices`/LUKS parts of the generated file: `modules/system/disko.nix` supplies those.
3. Repoint `modules/system/disko.nix` at your own disk (`ls /dev/disk/by-id/`). See [installing.md](installing.md) for the full from-scratch install.
4. Edit `variables.nix` — username, hostname, timezone/locale/keyboard, monitor names + layout, cursor theme. That's the only file you need to touch identity/preference-wise; everything else reads from it. Single monitor: point `secondaryMonitor.output` at the same name as `primaryMonitor.output` and drop the second `hl.monitor` block in `modules/home/hyprland.nix`.
5. Drop the modules that are tied to my hardware or apps. Delete their line from `modules/default.nix` (system modules) or `modules/home/default.nix` (home-manager ones), and the file if you like:
   - `apps/amazfit.nix` — a specific smartwatch.
   - `virtualisation/windows-vm.nix` + `virtualisation/audio-routing.nix` — a Windows VM for one Windows-only voice changer, plus the virtual mic that brings its output back to the host. They go together.
   - `gaming/vr.nix` — a specific headset workflow.
   - `network/protonvpn.nix` needs your own WireGuard config in `secrets/secrets.yaml` (see [protonvpn.md](protonvpn.md)); its `apps` list and `network/tor.nix`'s launcher are personal choices too.
   - `system/secrets.nix` is encrypted for my age key. Either re-encrypt for your own ([secrets.md](secrets.md)) or drop it together with `network/protonvpn.nix`.
6. Deploy ([deploying.md](deploying.md)), then work through [manual-setup.md](manual-setup.md) for what a rebuild can't do on its own.

Where a module depends on another one, `modules/default.nix` says so next to its line.
