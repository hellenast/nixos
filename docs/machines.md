# Machines

The repo describes several machines, one folder each in `hosts/`. A folder's name is that machine's hostname, and `flake.nix` builds one `nixosConfigurations` entry per folder, so `nixos-rebuild switch --flake .#` (no name after `#`) picks the right one on each machine.

| Machine | What it is |
|---|---|
| `hyena` | The desktop: AMD CPU, AMD graphics (a Radeon RX 9060 XT, plus the CPU's own), two monitors, US keyboard with dead keys. |
| `hyena-lt-home` | The home laptop: Intel CPU and its integrated graphics, ABNT2 keyboard. |
| `hyena-lt-work` | The work laptop: AMD CPU and its integrated graphics, plus an NVIDIA GPU for what's offloaded to it, ABNT2 keyboard. |

## Where the settings are

- **`variables.nix`** — what every machine shares: username, locale, timezone, cursor theme.
- **`hosts/<name>/variables.nix`** — what makes each machine different (below). It's merged over `variables.nix`, so it can also override anything there.
- **`hosts/<name>/hardware-configuration.nix`** — `nixos-generate-config` output for that machine (kernel modules, CPU microcode). The laptops start with placeholders; `fresh-install.sh` replaces them with the real thing when it installs them.

Both variables files reach every module as plain arguments (`specialArgs`), like `isLaptop` or `gpus` in a module's `{ ... }:` header. Every machine has to set every variable in the table below; a missing one fails the build with "called without required argument".

## The machine's variables

| Variable | What it does |
|---|---|
| `isLaptop` | `true`: suspend on lid close, battery and power-profile support, and brightness and the battery icon in the shell (see [Laptops](#laptops)). `false`: the machine never sleeps on its own. |
| `cpu` | `"amd"` or `"intel"`. Turns on Intel's thermal daemon on Intel laptops. (Microcode and KVM come from `hardware-configuration.nix`.) |
| `gpus` | Every GPU vendor in the machine: `"amd"`, `"intel"` and/or `"nvidia"`. Drives `modules/system/gpu.nix`: the driver loaded in the initrd for a native-resolution boot screen, Intel's video decoding, the NVIDIA driver, and PRIME when NVIDIA sits next to integrated graphics. |
| `gpuBusIds` | For NVIDIA PRIME only: the PCI address of each GPU, e.g. `{ amd = "PCI:6:0:0"; nvidia = "PCI:1:0:0"; }` (decimal; `lspci -D` shows them in hex). `fresh-install.sh` detects them. `{ }` elsewhere. |
| `disk` | The disk `fresh-install.sh` installs on, as a `/dev/disk/by-id/...` path; it sets this to the disk picked during the install. Only formatting uses it (the filesystems are found by partition label afterwards), so it can't break a running system. |
| `consoleKeyMap` | TTY keymap (`localectl list-keymaps`). A non-US one (the laptops' `br-abnt2`) is also loaded in the initrd, so the LUKS passphrase is typed the way the keys say (`modules/system/base.nix`). |
| `keyboardLayout`, `keyboardVariant`, `keyboardModel` | Hyprland's XKB layout, variant and model: `us`/`intl`/`""` on the desktop, `br`/`""`/`abnt2` on the laptops. `""` means none. |
| `monitors` | Hyprland outputs (`hyprctl monitors`) in order: `output`, `mode`, `position`, and optionally `scale` (default 1, or `"auto"`) and `transform` (0 = normal, 1 = 90°, 2 = 180°, 3 = 270°). Outputs not listed, like a laptop's external monitor, are laid out automatically at their preferred mode. The laptops list only the built-in screen, `eDP-1`, at `"preferred"` mode and `"auto"` scale. |
| `disabledModules` | Files in `modules/` this machine leaves out, e.g. `"gaming/vr.nix"` or `"home/apps/spotify.nix"` (the `home/` ones are home-manager modules). Every other module in `modules/default.nix` and `modules/home/default.nix` is installed. `fresh-install.sh`'s module picker writes this list. |

The laptops leave out the Windows VM and its virtual mic (`virtualisation/windows-vm.nix`, `virtualisation/audio-routing.nix`): both are built around the desktop's USB mic, and the VM starts at boot. `hyena-lt-home` also leaves out VR (`gaming/vr.nix`), which integrated graphics can't render.

## Laptops

With `isLaptop = true`:

- **Suspend.** Closing the lid suspends, unless an external monitor is connected ("docked"). caelestia-shell suspends after 10 idle minutes too, locking first; the dots' sleep bind (Super+Shift+L) and four-finger swipe down suspend as well (`modules/system/power.nix`, `modules/home/hyprland.nix`).
- **No hibernation.** Resuming would need the swapfile's offset inside the encrypted btrfs volume, which isn't set up, so hibernation is disabled outright, and "suspend then hibernate" falls back to plain suspend.
- **Battery and power.** UPower feeds the shell's battery icon and low-battery warnings; power-profiles-daemon adds the power saver / balanced / performance switch to the shell's dashboard; Intel CPUs get thermald.
- **The shell.** The battery icon, the brightness OSD and changing brightness by scrolling on the bar are on (`modules/home/caelestia.nix`). These are in the shell's initial `~/.config/caelestia/shell.json`, which is only written once, the first time home-manager runs on the machine: switching an installed machine to `isLaptop = true` later needs `rm ~/.config/caelestia/shell.json` and a rebuild to pick them up.

Touchpad, gestures and the brightness keys need nothing here: the caelestia dots' Hyprland config already handles them.

## NVIDIA (`hyena-lt-work`)

The AMD integrated graphics run the desktop and the built-in screen; the NVIDIA GPU only runs what's offloaded to it, and powers off entirely the rest of the time (`modules/system/gpu.nix`):

- Run an app on it with `nvidia-offload <command>`. For a Steam game, set its launch options to `nvidia-offload %command%`.
- The driver uses NVIDIA's open kernel modules, their recommendation for Turing (GTX 16xx, RTX 20xx) and newer. On an older card, set `hardware.nvidia.open = false` in `gpu.nix`.
- PRIME needs the PCI address of both GPUs (`gpuBusIds`). The ones committed for this laptop are typical values, not its own, until `fresh-install.sh` installs it and detects them.

## Adding a machine

The easy way: run `fresh-install.sh` on it and pick "a new machine" ([installing.md](installing.md)). It asks for a name, starts from a copy of the closest existing machine's settings, fills in its hardware, and generates its `hardware-configuration.nix`. Commit the new `hosts/<name>/` from `~/nixos` afterwards.

By hand:

1. Copy a machine's folder in `hosts/` to one named after the new hostname, and edit its `variables.nix`.
2. Generate its `hardware-configuration.nix` on the machine: `nixos-generate-config --show-hardware-config --no-filesystems > hosts/<name>/hardware-configuration.nix` (the filesystems come from `modules/system/disko.nix`).
3. Deploy ([deploying.md](deploying.md)), or install it from scratch ([installing.md](installing.md)).

## Shared between machines

- **The age key.** `secrets/secrets.yaml` is encrypted for one age key, so every machine needs that same key at `/var/lib/sops-nix/key.txt` ([secrets.md](secrets.md)). With a copy on the install stick, `fresh-install.sh` puts it there.
- **The repo.** Every machine gets all of `hosts/` in its deploy copy, but builds only its own.
