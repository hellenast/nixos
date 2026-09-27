# VMs and containers

Modules: `modules/virtualisation/`.

## Windows VM / Dubbing AI (`windows-vm.nix`, `audio-routing.nix`)

A Windows 10 VM for the Dubbing AI voice changer, which needs real Windows kernel drivers. The USB mic is passed through to the VM; the processed voice comes back to the host through a virtual mic.

### One-time setup

- Put a Windows 10 ISO at `~/isos/Win10.iso` before the VM first boots.
- After installing Windows, install the SPICE Guest Tools inside it. They make the QXL video device work (instead of a slow generic VGA driver) and provide clipboard sharing and cursor integration. Nix can't do this — it runs inside the guest.
- If the physical mic ever changes, look up its USB vendor/product id with `lsusb` and update `micVendorId`/`micProductId` in `windows-vm.nix`.

### Routing the voice (each time it's needed)

1. In the guest: turn on Dubbing AI's "Hear Myself", with output set to Speakers.
2. On the host: in `pavucontrol`'s Playback tab, route the VM's SPICE playback stream into `DubbingAI_Virtual_Mic`.

`audio-routing.nix` already makes the remapped `DubbingAI_Mic` source the system default input, so apps that use "the default mic" (Sober, ZapZap, ...) pick it up without per-app selection.

### State

The VM disk (`/var/lib/libvirt/images/dubbingai-win10.qcow2`) is real data that Nix doesn't rebuild. On a host reformat, restore it from a backup kept on another drive, or let the activation script create a blank disk and reinstall Windows + Dubbing AI. See [installing.md](installing.md).

## Waydroid (`waydroid.nix`)

Not running anything specific right now (it was set up for Minecraft Bedrock, which doesn't work in it — [gaming.md](gaming.md#what-didnt-work)), but this applies to any Android app installed in it.

### Setup

`virtualisation.waydroid.enable` handles the kernel config, LXC and D-Bus wiring. Everything after that is interactive:

```
sudo waydroid init -s GAPPS     # system image with Play Store (add -f if a plain init was already done)
waydroid session start          # then sign into a Google account in the window that opens
```

### Window size

The window doesn't resize live, and can't: single-window mode (the default) renders Android to one fixed-resolution virtual display, so dragging the window just stretches/crops it. Waydroid's multi-window mode is meant to give each app its own resizable window, but it's broken on Hyprland — open reports on both [Hyprland's](https://github.com/hyprwm/Hyprland/issues/6400) and [Waydroid's](https://github.com/waydroid/waydroid/issues/976) trackers describe black windows or mispositioned content. What works is single-window mode with an explicit resolution:

```
waydroid prop set persist.waydroid.multi_windows false
waydroid prop set persist.waydroid.width 2560
waydroid prop set persist.waydroid.height 1440
sudo systemctl restart waydroid-container
```

To change the size, re-run the `prop set` commands with other numbers and restart the container.

### Troubleshooting

- `waydroid status` shows `Session: RUNNING` but `Container: STOPPED`: check whether Android requested a reboot from inside (`journalctl -u waydroid-container`, look for `sys.powerctl='reboot,'`). The LXC container has nothing to reboot into, so Android's `init` shutting down just kills it. `sudo systemctl restart waydroid-container` brings it back.

### State

Only `/var/lib/waydroid/data` is worth backing up — Android's `/data`: installed apps, their data, signed-in accounts. It lives on the root subvolume, so a reformat wipes it. `/var/lib/waydroid/images` and `rootfs` are the downloaded Android build (`waydroid init` recreates them), and `waydroid.cfg` (including the resolution props above) is quick to redo. For the restore order after a reinstall, see [installing.md](installing.md#the-easy-way-fresh-installsh).
