# Modules

What each file does. Paths are relative to `modules/`. System modules are listed in `default.nix`; home-manager modules in `home/default.nix`. `fresh-install.sh` shows these descriptions in its module picker, so keep each entry's ``- **`file.nix`** — description`` shape.

**Where things go.** A feature that's purely user-level lives under `home/`. A feature that needs system-level config keeps both halves in one NixOS module under the matching folder, using a `home-manager.users.<name>` block for the user half (`desktop/thunar.nix`, `gaming/steam.nix`, `apps/amazfit.nix`), so dropping that one file removes the whole feature. Modules that need another flake's NixOS/home-manager module import it themselves.

## Top level

- **`../flake.nix`** — Inputs: nixpkgs-unstable, home-manager, nix-flatpak, caelestia-shell/cli, the caelestia dots repo (a plain source, not a flake; pieces of it are used directly, some patched), Zen, Helium, NixVirt, sops-nix, disko, bedrock-on-linux and Millennium. Builds one configuration per machine in `hosts/`: merges `variables.nix` with the machine's own, passes the result to every module as `specialArgs`, and leaves out the machine's `disabledModules`.
- **`../variables.nix`** — What every machine shares: username/description, timezone/locale, cursor theme.
- **`../hosts/<name>/variables.nix`** — Each machine's own: laptop or not, CPU, GPUs (+ NVIDIA PRIME bus IDs), install disk, keyboard, monitors, modules left out. See [machines.md](machines.md).
- **`../hosts/<name>/hardware-configuration.nix`** — Each machine's `nixos-generate-config` output: initrd kernel modules and CPU microcode. **Not portable.** No disk layout — that's `system/disko.nix`. The laptops' are placeholders until `fresh-install.sh` installs them.
- **`default.nix`** — The list of system modules, with dependencies between them noted. Every machine gets all of them, minus its `disabledModules`.

## `system/`

- **`disko.nix`** — Declarative disk layout: plaintext EFI partition, then one LUKS2 partition with a btrfs volume (root/home/nix/log/persist subvolumes + a swapfile subvolume). Applied once during install ([installing.md](installing.md)); on normal rebuilds it supplies `fileSystems`/`swapDevices`/LUKS config. The disk is the machine's `disk` (by id); only formatting uses it.
- **`boot.nix`** — systemd-boot, a systemd-based initrd (needed for Plymouth to draw the LUKS prompt), and a Plymouth splash/unlock screen in caelestia's "hard" dark colours.
- **`gpu.nix`** — From the machine's `gpus`: graphics (+32-bit), amdgpu/i915 in the initrd so the splash runs at native resolution, Intel's VA-API driver, and the NVIDIA driver — open kernel modules, and on a hybrid laptop PRIME render offload (`nvidia-offload`) with the NVIDIA GPU powered off when unused.
- **`hardware.nix`** — Bluetooth + blueman, fwupd.
- **`base.nix`** — Hostname, NetworkManager, timezone/locale/console keymap (also loaded in the initrd for non-US keymaps, for the LUKS passphrase), the user account (fish as shell), basic CLI tools, `system.stateVersion`.
- **`nix.nix`** — Flakes, unfree packages, daily garbage collection (keeps a week), nix-ld for prebuilt binaries.
- **`memory.nix`** — Lower `vm.swappiness`, zram as compressed in-RAM swap ahead of the disk swapfile, and earlyoom to kill runaway processes before the desktop freezes.
- **`power.nix`** — From the machine's `isLaptop`. Desktop: sleep, suspend and hibernate disabled outright; lid switch ignored. Laptop: suspend on lid close (unless docked), no hibernation, UPower, power-profiles-daemon, and thermald on Intel.
- **`secrets.nix`** — sops-nix: decrypts `secrets/secrets.yaml` into root-only files under `/run/secrets/` at activation. Currently holds the ProtonVPN WireGuard config. See [secrets.md](secrets.md).

## `desktop/`

- **`session.nix`** — Hyprland, greetd logging straight into it (no greeter — LUKS already gates boot), xdg-desktop-portals, polkit with a GUI agent.
- **`audio.nix`** — PipeWire with ALSA (+32-bit) and PulseAudio compatibility.
- **`caelestia.nix`** — System-side support for caelestia-shell: its fonts, dconf (for GTK theme writes), and a passwordless sudo rule for the `papirus-folders` call caelestia makes on every scheme change.
- **`thunar.nix`** — Thunar with the archive plugin, gvfs (trash, network locations), engrampa + zip/unzip/p7zip, and the dots' Thunar config with kitty as "Open Terminal Here".
- **`flatpak.nix`** — System-wide Flatpak (nix-flatpak) with Flathub, daily auto-updates plus an update on every boot. Apps are declared by the modules that use them.

## `apps/`

- **`dev.nix`** — Docker (socket-activated, not started at boot), a Rancher server container (started by hand), kubectl/helm/rancher CLI, docker-compose/buildx, node/bun/pnpm, Cypress, Beekeeper Studio, Insomnia. Postgres runs per project through docker-compose.
- **`ai.nix`** — Claude Code, mainly for `claude rc` (remote control from phone/browser).
- **`amazfit.nix`** — Amazfish (Flatpak) for an Amazfit GTR2e watch, a packaged `huami-token`, and `amazfit-get-key.sh` to fetch the watch's pairing key.

## `gaming/`

- **`steam.nix`** — Steam with Millennium injected (client modding), Remote Play/dedicated-server firewall rules, a gamescope session, gamescope, GameMode — and the caelestia-themed Material skin for the Steam client (the home-manager half).
- **`minecraft.nix`** — Prism Launcher (Java Edition) and bedrock-on-linux (Bedrock Edition: the Windows GDK build under Proton).
- **`roblox.nix`** — Sober (Roblox) from Flathub.
- **`vr.nix`** — ALVR server + firewall ports, streaming SteamVR to a standalone headset.

## `virtualisation/`

- **`windows-vm.nix`** — A libvirt/KVM Windows 10 VM ("dubbingai-win10") declared with NixVirt, for the Windows-only Dubbing AI voice changer: USB mic passthrough by id (with udev rules so the host never grabs the mic), SPICE for display/audio, an activation script that creates the disk image if missing.
- **`audio-routing.nix`** — A PipeWire virtual mic (null sink + remapped monitor source, set as the default input) that the VM's processed voice is routed into, so any host app can use it. Plus pavucontrol and qpwgraph.
- **`waydroid.nix`** — A real Android container for Android apps without a Linux build. Uses the nftables package variant, since this kernel has no `ip_tables`.

## `network/`

- **`protonvpn.nix`** — Per-app ProtonVPN: a network namespace with its own WireGuard tunnel, a `protonvpn-run` wrapper, and a "<Name> (VPN)" launcher for each app in its `apps` list. See [protonvpn.md](protonvpn.md).
- **`tor.nix`** — The Tor daemon (SOCKS on `127.0.0.1:9050`) and a "Vesktop (Tor)" launcher using Chromium's `--proxy-server`.

## `home/` (home-manager)

- **`default.nix`** — Entry point: identity, XDG user dirs, cursor theme, Bitwarden, Bottles, the `' + c → ç` compose override, and `update-flake.sh`.
- **`caelestia.nix`** — caelestia-shell + CLI: a patched shell package (working "Keep awake" toggle), CLI theme settings, shell.json seeded once (so its settings GUI can save; brightness and the battery icon on for laptops), a writable Papirus copy for folder recolouring, rendering user templates on every activation, and the `caelestia.postHooks` option other modules use to run commands on scheme changes.
- **`hyprland.nix`** — The dots' Hyprland config (with `rules.lua` patched to keep Vesktop out of the communication scratchpad), `hypr-user.lua` overrides (keyboard and monitors from the machine's variables, cursor, env vars, kitty, screenshot binds), the dots' sleep bind switched to plain suspend on laptops, and the screenshot scripts.
- **`terminal.nix`** — kitty, fish with the dots' config, starship, fastfetch with a custom logo, btop.
- **`apps/zen.nix`** — Zen browser, default browser, live-themed through the CaelestiaZen Sine mod, plus the dots' `userChrome.css`.
- **`apps/helium.nix`** — Helium browser, themed with a Chrome theme generated from the scheme.
- **`apps/vscodium.nix`** — VSCodium with the dots' settings and theme extension, and its theme synced before each launch and on scheme changes.
- **`apps/vesktop.nix`** — Vesktop (Discord), caelestia theme, kept out of the scratchpad toggle and un-maximized on every activation.
- **`apps/spotify.nix`** — Spotify as a user-scope Flatpak, spicetify with the caelestia theme, re-applied on scheme changes, and the music scratchpad toggle.
- **`apps/zapzap.nix`** — ZapZap (WhatsApp): WhatsApp Web CSS and a patched Qt palette, both from the scheme.
- **`apps/media.nix`** — VLC (default for video/audio), Krita, Drawing, Webcamoid.

The manual steps each of these needs are in [manual-setup.md](manual-setup.md) and the pages it links.
