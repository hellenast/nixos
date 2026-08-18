# nixos

<img width="2560" height="1440" alt="Screenshot_2026-08-17_14-31-32" src="https://github.com/user-attachments/assets/b71220f4-7a07-47f7-8b13-44e40ff8364f" />

Personal NixOS + Hyprland + [caelestia-shell](https://github.com/caelestia-dots/shell) flake config, built to be forkable — everything specific to this person's machine (username, hostname, locale, monitor layout, cursor theme) lives in one file, `variables.nix`. Declarative except for a handful of things noted below that genuinely can't be (accounts, pairing, stateful data).

## Using this on your own machine

1. Fork/clone the repo.
2. Regenerate `hardware-configuration.nix` for your actual hardware (`nixos-generate-config`) — disk UUIDs, kernel modules, and CPU microcode are never portable between machines.
3. Edit `variables.nix` — username, hostname, timezone/locale/keyboard, monitor names + layout, cursor theme. That's the only file identity/preference-wise you need to touch; everything else reads from it.
4. A few modules are tied to hardware or apps specific to this setup and probably don't apply to you: `amazfit.nix` (a specific watch), `windows-vm.nix` + `audio-routing.nix` (a Windows VM running one particular Windows-only app, plus the virtual mic that feeds its output back into the host), `vr.nix` (a specific headset workflow). Delete the ones you don't want from `flake.nix`'s `modules` list and from disk.
5. `protonvpn.nix`'s `apps` list and `tor.nix`'s launcher are also personal choices — edit or remove them.
6. See "Manual setup" below for anything that can't be handled by `nixos-rebuild` alone (secrets, device pairing).

## Deploying

```
sudo mkdir -p /etc/nixos/secrets && sudo cp ~/nixos/secrets/secrets.yaml /etc/nixos/secrets/secrets.yaml && sudo cp ~/nixos/*.nix /etc/nixos/ && cd /etc/nixos && sudo nixos-rebuild switch --flake .#
```

`nixos-rebuild switch --flake .#` (no name after `#`) picks the `nixosConfigurations` attribute matching the machine's actual hostname — so this only works as-is on a host whose hostname matches `hostname` in `variables.nix`.

The `mkdir`/`cp` at the front handles `secrets/secrets.yaml` (see `secrets.nix`) explicitly — the `*.nix` glob that follows only ever matches `.nix` files, so that secret wouldn't come along on its own otherwise.

## Files

### `variables.nix`
Single source of truth for everything specific to this person/machine: `username`/`userDescription`/`hostname`, timezone/locale/console keymap, Hyprland keyboard layout/variant, monitor names + layout (`primaryMonitor`/`secondaryMonitor`), and cursor theme/size. Threaded into every other module as `specialArgs` via `flake.nix`, so adapting this repo to a different person/machine is (mostly) a one-file edit.

### `flake.nix`
Entry point. Pulls in nixpkgs-unstable, home-manager, nix-flatpak, caelestia-shell/cli, the caelestia-dots repo (vendored as a plain source, not a flake — pieces of it get patched/re-sourced directly in `home.nix`), zen-browser, and NixVirt. Imports `variables.nix` and spreads it into `specialArgs`/`extraSpecialArgs` for every module below.

### `configuration.nix`
Core system config: systemd-boot/UEFI, NetworkManager, timezone/locale, AMD graphics, Hyprland, memory tuning (lowered `vm.swappiness` + zram as compressed RAM-backed swap, ahead of the disk swap partition in `hardware-configuration.nix`), xdg-desktop-portals, polkit agent, sleep/suspend disabled outright, PipeWire audio, fonts, Bluetooth, gvfs (needed for Thunar's trash support), system-wide Flatpak (Sober/Roblox, with weekly auto-updates), the user account itself, and base CLI tools (git, curl, wget, usbutils). The login screen itself is also here: greetd running regreet (a themed GTK greeter) inside a minimal, single-purpose sway session — sway specifically because it can target an output by name, which is what actually gets the greeter onto the main monitor (`variables.nix` -> `primaryMonitor`) instead of spanning/landing on the wrong one; regreet's own default (cage) can't do that. No autologin — every boot/logout prompts for a password before Hyprland starts.

### `home.nix`
The bulk of the actual desktop environment, managed via home-manager. Caelestia shell + CLI configuration (theming toggles, scratchpad apps for btop/Discord/Spotify), Zen as the default browser, Kitty as the terminal (with a custom font + transparency), the app package list (Vesktop, Spicetify, VSCodium, Thunar + archive plugins, screenshot tooling, etc.), the vendored Hyprland config from the dots plus a `hypr-user.lua` override file (keyboard layout, monitor layout, cursor theme, custom screenshot keybinds, kitty as the default terminal instead of foot — all read from `variables.nix`), vendored fish/spicetify/Thunar/VSCodium configs, and a patched copy of the dots' `rules.lua` (excludes Vesktop from a scratchpad workspace group it shouldn't be in). Single-monitor setups: point `secondaryMonitor.output` in `variables.nix` at the same name as `primaryMonitor.output` and drop the second `hl.monitor` block here.

### `media.nix`
VLC (video/audio, set as the default app for common media MIME types), Krita, and Drawing (lightweight image crop/rotate/annotate).

### `dev.nix`
Docker (installed but not started at boot — starts on demand the first time `docker` is actually used), the user added to the `docker` group, a Rancher server container for local Kubernetes cluster management (also not auto-started — `systemctl start docker-rancher` when wanted), and CLI/GUI dev tooling: kubectl, helm, the `rancher` CLI, docker-compose/buildx, Cypress (E2E testing), Beekeeper Studio (DB client), Insomnia (API client), plus node/bun/pnpm for frontend (React/Next.js) work. No `services.postgresql` — Postgres for these projects runs per-project via docker-compose instead.

### `amazfit.nix`
Amazfish (Flatpak) as the companion app for an Amazfit GTR2e watch, a custom-packaged `huami-token` CLI, and a `amazfit-get-key.sh` helper script that fetches the watch's Bluetooth pairing key from Huami/Zepp's servers. See Manual Setup below — this one has real interactive steps every time the watch is re-paired.

### `gaming.nix`
Steam (Remote Play + dedicated-server firewall rules, gamescope session for fullscreen game launches), gamescope itself, and GameMode for automatic per-game performance tweaks.

### `vr.nix`
ALVR — streams SteamVR content to a standalone headset (Quest, etc.) over Wi-Fi. Just the server + firewall ports; headset pairing itself is outside Nix.

### `windows-vm.nix`
A KVM/QEMU/libvirt-managed Windows 10 VM ("dubbingai-win10"), declared via NixVirt, with USB mic passthrough by vendor/product ID and SPICE for display/audio. Exists specifically to run a Windows-only voice-changer app ("Dubbing AI") that needs real kernel-mode drivers. The VM's disk is genuinely stateful (the actual Windows install lives there, not something Nix can rebuild) — see Manual Setup.

### `protonvpn.nix`
Per-app ProtonVPN split tunneling: a dedicated network namespace with its own WireGuard tunnel (via `wg-quick`), a `protonvpn-run` wrapper, and a "<Name> (VPN)" launcher for each app listed in the module's `apps` list — only those apps' traffic goes through the VPN, everything else keeps using the normal default route. See Manual Setup below for the one-time WireGuard config placement.

### `tor.nix`
System Tor daemon (client-only, exposing the standard local SOCKS proxy on `127.0.0.1:9050`) plus a "Vesktop (Tor)" launcher — a wrapper script + desktop item that starts Vesktop with `--proxy-server="socks5://127.0.0.1:9050"`, routing it (including DNS) through Tor. Used the same way as `protonvpn.nix` — to work around Discord's regional video-sharing block — but via Chromium's native `--proxy-server` flag rather than a routed VPN tunnel, since torsocks-style LD_PRELOAD wrapping doesn't work on Electron/Chromium's own network stack.

### `audio-routing.nix`
A PipeWire virtual-mic (null sink + a `module-remap-source`-wrapped copy of its paired monitor source, since apps and pickers hide raw monitor sources from mic-input lists), run as a systemd user service, used to feed the Windows VM's voice-changer output into any host app's default mic input (Discord, games, etc.).

### `caelestia-system.nix`
System-level plumbing caelestia-shell's dynamic theming needs but that home-manager can't provide on its own: enables dconf (GTK theme writes), and passwordless sudo rules so caelestia's hardcoded `sudo -n papirus-folders` call (used to recolor folder icons on every theme switch) doesn't prompt for a password each time.

### `secrets.nix`
[sops-nix](https://github.com/Mic92/sops-nix), decrypting `secrets/secrets.yaml` (age-encrypted, safe to commit — see `.sops.yaml`) into root-only files under `/run/secrets/` at activation time. Currently holds the ProtonVPN WireGuard config that `protonvpn.nix` reads back out. See Manual Setup below for the one-time age key placement a fresh machine needs.

### `firmware.nix`
`services.fwupd.enable = true` — checks the LVFS for firmware updates (BIOS/UEFI, SSDs, supported peripherals). Nothing automatic: run `fwupdmgr refresh && fwupdmgr update` by hand when you want to check.

### `oom.nix`
`earlyoom`, tuned to kill the worst offending process once free memory drops under 5% and free swap under 10%, before the kernel's own OOM killer would even engage (by which point the system is usually already frozen). Notifies via `libnotify` when it kills something. Complements the zram/swappiness tuning in `configuration.nix`.

### `hardware-configuration.nix`
Auto-generated by `nixos-generate-config`. Filesystem UUIDs, kernel modules, CPU microcode — specific to this exact machine's disks and hardware. **Not portable.** A different machine needs its own freshly generated copy, not this one.

## Staying updated

Flatpak apps (Sober, Spotify) update themselves on a weekly systemd timer — `services.flatpak.update.auto`, no action needed. One caveat: an update to Spotify overwrites spicetify's in-place patch until something re-applies it, which happens somewhat naturally (`caelestia-spotify-resync.sh` runs `spicetify apply` on every theme/scheme change) but isn't instant — if Spotify looks unthemed right after an update, change the wallpaper once or run `spicetify apply` by hand.

Everything else (nixpkgs, home-manager, caelestia-shell/cli, zen-browser, NixVirt) is pinned in `flake.lock` and does *not* auto-update — a bad bump is the kind of thing worth reviewing before committing to, and deploying needs an interactive `sudo` password regardless. Run `update-flake.sh` to refresh `flake.lock` and see what changed (shows a `git diff` if the repo is under git), then deploy the usual way once you've looked it over (see Deploying above):
```
sudo mkdir -p /etc/nixos/secrets && sudo cp ~/nixos/secrets/secrets.yaml /etc/nixos/secrets/secrets.yaml && sudo cp ~/nixos/*.nix /etc/nixos/ && cd /etc/nixos && sudo nixos-rebuild switch --flake .#
```

## Manual setup

Things a plain `nixos-rebuild switch` can't do for you — either because they're inherently interactive (account logins, device pairing, 2FA), or because they involve real stateful data Nix deliberately doesn't touch.

### Every fresh install / new machine
- Regenerate `hardware-configuration.nix` for the actual hardware (`nixos-generate-config`).
- Update `variables.nix` — at minimum `username`/`userDescription`/`hostname`; also monitor names/layout and cursor theme if this machine's setup differs (see "Using this on your own machine" above).
- Log out and back in (or reboot) once after the first deploy — group memberships (`docker`, `libvirtd`, `wheel`, `video`, `audio`) only take effect on next login, not immediately after `nixos-rebuild switch`.
- Secrets (`secrets.nix`) won't decrypt on a machine that's never seen the age private key before — see the "Secrets" section below, this needs doing *before* the first `nixos-rebuild switch` that references a `sops.secrets.*` value (currently just ProtonVPN).

### Secrets (`secrets.nix`)
`secrets/secrets.yaml` is encrypted for one age public key (declared in `.sops.yaml`) and is safe to have in a public repo — only the matching private key can decrypt it, and that key never touches this repo. Decryption happens at system activation, so the private key has to already be on disk as `/var/lib/sops-nix/key.txt` (root-only, `0400`) *before* the first rebuild that needs it — Nix can't put it there for you, same reasoning as the old ProtonVPN file used to be manual. On a new machine (or if the key is ever lost): generate a fresh age keypair, install the private half at that path, then re-encrypt `secrets/secrets.yaml` for the new public key with `sops updatekeys` (after updating `.sops.yaml` to match) so the new machine can actually read it.

Editing an existing secret: `sops secrets/secrets.yaml` (needs `SOPS_AGE_KEY_FILE` pointed at the private key, or the key already at its default lookup path) opens it decrypted in `$EDITOR` and re-encrypts on save. The `*.nix` glob in the deploy command doesn't pick up `secrets/secrets.yaml` — see Deploying above for the extra copy step whenever this file changes.

### Amazfit watch (`amazfit.nix`)
1. Pair and sync the watch at least once through the official Zepp mobile app first — `huami-token` can't find a device that's never synced.
2. Run `amazfit-get-key.sh` and type the Zepp account email/password when prompted (password goes straight to `huami-token`, never stored anywhere).
3. Copy the printed auth key into Amazfish: Settings > Device > Auth Key.
4. Repeat 2–3 any time the watch is unpaired and re-paired.

### Spotify (`home.nix`)
- Installed as a user-scope Flatpak so spicetify can patch it — log into Spotify normally on first launch.
- Live theme sync doesn't work under Flatpak (`spicetify watch` crashes outside its sandbox), so colors only update via a postHook script on scheme change — restart Spotify by hand to actually see the new theme.

### VSCodium Caelestia integration
- The extension is installed once from a vendored `.vsix` and then left alone (so it can regenerate its own theme file without Nix stomping it every rebuild) — an actual extension version bump requires manually deleting the installed extension directory first so it reinstalls.

### Docker / Rancher (`dev.nix`)
- Both are deliberately not auto-started, to avoid idle resource usage. Just running any `docker` command starts the daemon on demand; Rancher needs `systemctl start docker-rancher` explicitly.
- First visit to the Rancher GUI (`https://localhost:8443`) will walk through its own first-run admin account setup.

### Windows VM / Dubbing AI (`windows-vm.nix`, `audio-routing.nix`)
- Needs a Windows 10 ISO manually placed at `~/isos/Win10.iso` before the VM can boot for the first time.
- The VM's disk (`/var/lib/libvirt/images/dubbingai-win10.qcow2`) is real, stateful data — not rebuilt by Nix. On a host reformat: restore it from a backup kept on a separate drive, or let the activation script create a blank disk and manually reinstall Windows + Dubbing AI from scratch.
- If the physical mic ever changes, re-check its USB vendor/product ID with `lsusb` and update `micVendorId`/`micProductId`.
- Routing audio actually requires, each time it's needed: inside the guest, turn on Dubbing AI's "Hear Myself" with output set to Speakers; on the host, route the VM's SPICE playback stream into `DubbingAI_Virtual_Mic` via `pavucontrol`'s Playback tab. The `audio-routing.nix` service already sets the remapped `DubbingAI_Mic` source as the system default input, so apps that just use "the default mic" (Sober, Zapzap, etc.) pick it up automatically — no per-app source selection needed.

### ProtonVPN (`protonvpn.nix`, `secrets.nix`)
- The WireGuard config lives encrypted in `secrets/secrets.yaml` (via sops-nix, see `secrets.nix`), not as a plain file — see `PROTON-VPN-WIREGUARD.md` for the full get-a-config / encrypt-it / deploy walkthrough, including how to swap in a new config later.
- Edit the `apps` list in `protonvpn.nix` to name whichever apps should go through the VPN (Vesktop is in there already), then redeploy — each gets its own "<Name> (VPN)" launcher next to its normal one.
- The tunnel comes up on its own at every boot (`protonvpn-netns`/`protonvpn-wg` are both `wantedBy multi-user.target`) — no manual start needed after the first setup.

### ALVR / VR headset (`vr.nix`)
- Headset pairing (installing the ALVR client APK on the headset, connecting it to this PC) is an interactive step outside of Nix, done once per headset.
- SteamVR itself needs installing/configuring through Steam.

### GameMode (`gaming.nix`)
- Applies automatically to anything launched through Steam. For anything else, add `gamemoderun %command%` to that game's launch options by hand.
