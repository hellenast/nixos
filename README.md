# nixos

<img width="2560" height="1440" alt="Screenshot_2026-08-17_14-31-32" src="https://github.com/user-attachments/assets/b71220f4-7a07-47f7-8b13-44e40ff8364f" />

My personal NixOS + Hyprland + [caelestia-shell](https://github.com/caelestia-dots/shell) flake config, built to be forkable — everything specific to my machine (username, hostname, locale, monitor layout, cursor theme) lives in one file, `variables.nix`. It's declarative except for a handful of things noted below that genuinely can't be (accounts, pairing, stateful data).

## Using this on your own machine

1. Fork/clone the repo.
2. Regenerate `hardware-configuration.nix` for your actual hardware (`nixos-generate-config`) — kernel modules and CPU microcode are never portable between machines. Repoint `disko.nix` at your own disk too (`ls /dev/disk/by-id/`) — see "Reinstalling with full-disk encryption" below for the full from-scratch install flow.
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
My single source of truth for everything specific to my machine: `username`/`userDescription`/`hostname`, timezone/locale/console keymap, Hyprland keyboard layout/variant, monitor names + layout (`primaryMonitor`/`secondaryMonitor`), and cursor theme/size. It's threaded into every other module as `specialArgs` via `flake.nix`, so adapting this repo to a different person/machine is (mostly) a one-file edit.

### `flake.nix`
Entry point. Pulls in nixpkgs-unstable, home-manager, nix-flatpak, caelestia-shell/cli, the caelestia-dots repo (vendored as a plain source, not a flake — pieces of it get patched/re-sourced directly in `home.nix`), zen-browser, NixVirt, sops-nix, and disko (disk partitioning, see `disko.nix`). Imports `variables.nix` and spreads it into `specialArgs`/`extraSpecialArgs` for every module below.

### `configuration.nix`
My core system config: systemd-boot/UEFI, a systemd-based initrd (needed for Plymouth to theme the LUKS unlock screen — the classic initrd shows that prompt as plain text before Plymouth ever starts), a Plymouth splash/unlock screen colored to match caelestia-shell's current "hard" dark scheme, NetworkManager, timezone/locale, AMD graphics, Hyprland, memory tuning (lowered `vm.swappiness` + zram as compressed RAM-backed swap, ahead of the disk swapfile in `disko.nix`), xdg-desktop-portals, polkit agent, sleep/suspend disabled outright, PipeWire audio, fonts, Bluetooth, gvfs (needed for Thunar's trash support), system-wide Flatpak (Sober/Roblox, with daily auto-updates), the user account itself, and base CLI tools (git, curl, wget, usbutils). The login screen itself is also here: greetd autologs straight into Hyprland, no greeter prompt of its own — LUKS already gates access at boot, so a second password prompt on top of that would just be redundant.

### `home.nix`
The bulk of my actual desktop environment, managed via home-manager. Caelestia shell + CLI configuration (theming toggles, scratchpad apps for btop/Discord/Spotify), Zen as the default browser, Kitty as the terminal (with a custom font + transparency), the app package list (Vesktop, Spicetify, VSCodium, Thunar + archive plugins, screenshot tooling, etc.), the vendored Hyprland config from the dots plus a `hypr-user.lua` override file (keyboard layout, monitor layout, and cursor theme, all read from `variables.nix`; plus hardcoded custom screenshot keybinds and kitty as the default terminal instead of foot), vendored fish/spicetify/Thunar/VSCodium configs, and a patched copy of the dots' `rules.lua` (excludes Vesktop from a scratchpad workspace group it shouldn't be in). Single-monitor setups: point `secondaryMonitor.output` in `variables.nix` at the same name as `primaryMonitor.output` and drop the second `hl.monitor` block here.

### `media.nix`
VLC (video/audio, set as the default app for common media MIME types), Krita, and Drawing (lightweight image crop/rotate/annotate).

### `dev.nix`
Docker (installed but not started at boot — starts on demand the first time `docker` is actually used), the user added to the `docker` group, a Rancher server container for local Kubernetes cluster management (also not auto-started — `systemctl start docker-rancher` when wanted), and CLI/GUI dev tooling: kubectl, helm, the `rancher` CLI, docker-compose/buildx, Cypress (E2E testing), Beekeeper Studio (DB client), Insomnia (API client), plus node/bun/pnpm for frontend (React/Next.js) work. No `services.postgresql` — Postgres for these projects runs per-project via docker-compose instead.

### `amazfit.nix`
Amazfish (Flatpak) as the companion app for my Amazfit GTR2e watch, a custom-packaged `huami-token` CLI, and an `amazfit-get-key.sh` helper script that fetches the watch's Bluetooth pairing key from Huami/Zepp's servers. See Manual Setup below — this one has real interactive steps every time I re-pair the watch.

### `gaming.nix`
Steam (Remote Play + dedicated-server firewall rules, gamescope session for fullscreen game launches), gamescope itself, and GameMode for automatic per-game performance tweaks.

### `vr.nix`
ALVR — streams SteamVR content to a standalone headset (Quest, etc.) over Wi-Fi. Just the server + firewall ports; headset pairing itself is outside Nix.

### `windows-vm.nix`
A KVM/QEMU/libvirt-managed Windows 10 VM ("dubbingai-win10"), declared via NixVirt, with USB mic passthrough by vendor/product ID and SPICE for display/audio. I run this specifically for a Windows-only voice-changer app ("Dubbing AI") that needs real kernel-mode drivers. The VM's disk is genuinely stateful (the actual Windows install lives there, not something Nix can rebuild) — see Manual Setup.

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
`services.fwupd.enable = true` — checks the LVFS for firmware updates (BIOS/UEFI, SSDs, supported peripherals). Nothing automatic: I run `fwupdmgr refresh && fwupdmgr update` by hand whenever I want to check.

### `oom.nix`
`earlyoom`, tuned to kill the worst offending process once free memory drops under 5% and free swap under 10%, before the kernel's own OOM killer would even engage (by which point the system is usually already frozen). Notifies via `libnotify` when it kills something. Complements the zram/swappiness tuning in `configuration.nix`.

### `hardware-configuration.nix`
Machine-specific initrd kernel modules and CPU microcode only — **not portable**; a different machine needs `nixos-generate-config`'s own output for this part. Disk layout (`fileSystems`, `swapDevices`, LUKS unlocking) intentionally isn't here anymore; that's `disko.nix` now.

### `disko.nix`
Declarative full-disk layout, applied once via [disko](https://github.com/nix-community/disko) during a from-scratch install instead of partitioning/formatting by hand: an unencrypted EFI System Partition, then a single LUKS2-encrypted partition holding a btrfs volume with the root/home/nix/log/persist subvolumes plus a swapfile subvolume — so everything except `/boot` sits behind one passphrase, entered once at every boot. See "Reinstalling with full-disk encryption" below. **Not portable as-is** — it hardcodes this machine's disk by `/dev/disk/by-id`.

## Reinstalling with full-disk encryption

My machine was originally installed without disk encryption; `disko.nix` describes the encrypted layout it should have going forward. Since LUKS reformats the partition it lives on, applying it means backing up and reinstalling — there's no in-place upgrade path. Once done, this whole procedure only needs repeating if the disk itself is ever wiped again.

One wrinkle either way: `secrets.nix`/`protonvpn.nix` need an age private key at `/var/lib/sops-nix/key.txt` to decrypt `secrets/secrets.yaml` (see "Secrets" below), and a from-scratch install has no such key yet. Left enabled, `nixos-install` fails during activation trying to decrypt a secret it has no key for. Both paths below deal with this by disabling those modules for the initial install, then re-enabling them afterward once the key is back in place.

1. **Back up everything.** `/home` and `/persist` hold real data; `/var/lib/libvirt/images` (the Windows VM disk, see `windows-vm.nix`) is large stateful data Nix doesn't manage and won't recreate; and `/var/lib/sops-nix/key.txt` is my age private key — without a copy of it, `secrets/secrets.yaml` is unreadable after reinstall and I have to fall back to generating a fresh keypair and re-encrypting (see "Secrets" below). Copy all of these somewhere separate if they're worth keeping, or plan to reinstall Windows from scratch / regenerate the key.
2. Boot the machine from a [NixOS live ISO](https://nixos.org/download) (USB installer) with network access.

### The easy way: `fresh-install.sh`

I use this script for everything from here on, instead of doing it by hand. It finds a USB stick with this repo on it, copies it to `/root/nixos-config`, checks the disk id `disko.nix` targets against the actual hardware (prompting me to fix it first if it's drifted), comments out `./secrets.nix`, `./protonvpn.nix`, and the sops-nix module in that copy (the age-key problem above), then runs disko and `nixos-install`, prompts me to set the user password, and copies the patched config into `/mnt/etc/nixos`.

```
sudo bash fresh-install.sh
```

It prompts for confirmation before wiping the target disk. Once it's done and I've rebooted:

1. Restore `/var/lib/sops-nix/key.txt` from backup (or generate a fresh keypair and `sops updatekeys` — see "Secrets" below).
2. Uncomment `./secrets.nix`, `./protonvpn.nix`, and `inputs.sops-nix.nixosModules.sops` back in `/etc/nixos/flake.nix`.
3. `sudo nixos-rebuild switch --flake /etc/nixos#hyena`.
4. Restore `/home`, `/persist`, and (if kept) the Windows VM disk from the backup made in step 1 above.

### The manual way

Same result, one step at a time — useful if I want to see/adjust each step, or the script doesn't apply (different disk, different flake target name).

1. Clone this repo into the live environment (e.g. `nix-shell -p git --run "git clone <this repo's url> ~/nixos"`).
2. Confirm the disk id `disko.nix` targets is still correct on this exact drive: `ls /dev/disk/by-id/ | grep nvme` and compare against the `device` line in `disko.nix`. Update it first if it's changed.
3. Partition, LUKS-format, create the btrfs subvolumes, and mount everything to `/mnt` in one step:
   ```
   sudo nix run github:nix-community/disko -- --mode disko --flake ~/nixos#<hostname>
   ```
   This prompts for a LUKS passphrase (twice, to confirm) — pick one you'll be typing on every boot from now on.
4. If I have my old age key backed up, restore it now so secrets decrypt on first boot: `sudo install -D -m 0400 -o root -g root <age-key-file> /mnt/var/lib/sops-nix/key.txt`. If not, comment out `./secrets.nix`, `./protonvpn.nix`, and `inputs.sops-nix.nixosModules.sops` in `~/nixos/flake.nix` — the same patch `fresh-install.sh` applies — and plan to re-enable them after first boot per the "easy way" steps above.
5. Copy `secrets/secrets.yaml` into place the same way the normal deploy does (see Deploying above), but rooted at `/mnt` (skip this if I disabled `secrets.nix` in step 4):
   ```
   sudo mkdir -p /mnt/etc/nixos/secrets && sudo cp ~/nixos/secrets/secrets.yaml /mnt/etc/nixos/secrets/secrets.yaml && sudo cp ~/nixos/*.nix /mnt/etc/nixos/
   ```
6. Install:
   ```
   sudo nixos-install --root /mnt --flake /mnt/etc/nixos#<hostname>
   ```
   `nixos-install` will ask me to set a root password — anything works, it's a fallback console login, not what I use day to day (greetd autologs into Hyprland, see `configuration.nix`).
7. Reboot, remove the USB. The firmware boots the plaintext ESP, systemd-boot loads the kernel/initrd, and the initrd is what actually prompts for the LUKS passphrase before anything else can start.
8. Restore `/home`, `/persist`, and (if kept) the Windows VM disk from the backup made in step 1 above.

No manual `cryptsetup`/`mkfs`/subvolume/`mount` commands anywhere in this — `disko.nix` is the single source of truth for the disk layout, same as `variables.nix` is for identity/preferences.

## Staying updated

Flatpak apps update themselves via `services.flatpak.update.auto`, no action needed from me — Sober on a daily systemd timer (`configuration.nix`, plus a same-day catch-up on every boot), Spotify on a weekly one (`home.nix`, user-scope). One caveat: an update to Spotify overwrites spicetify's in-place patch until something re-applies it, which happens somewhat naturally (`caelestia-spotify-resync.sh` runs `spicetify apply` on every theme/scheme change) but isn't instant — if Spotify looks unthemed right after an update, I change the wallpaper once or run `spicetify apply` by hand.

Everything else (nixpkgs, home-manager, caelestia-shell/cli, zen-browser, NixVirt) is pinned in `flake.lock` and does *not* auto-update — a bad bump is the kind of thing worth reviewing before committing to, and deploying needs an interactive `sudo` password regardless. I run `update-flake.sh` to refresh `flake.lock` and see what changed (shows a `git diff` if the repo is under git), then deploy the usual way once I've looked it over (see Deploying above):
```
sudo mkdir -p /etc/nixos/secrets && sudo cp ~/nixos/secrets/secrets.yaml /etc/nixos/secrets/secrets.yaml && sudo cp ~/nixos/*.nix /etc/nixos/ && cd /etc/nixos && sudo nixos-rebuild switch --flake .#
```

## Manual setup

Things a plain `nixos-rebuild switch` can't do for you — either because they're inherently interactive (account logins, device pairing, 2FA), or because they involve real stateful data Nix deliberately doesn't touch.

### Every fresh install / new machine
- Regenerate `hardware-configuration.nix` for the actual hardware (`nixos-generate-config`).
- Update `variables.nix` — at minimum `username`/`userDescription`/`hostname`; also monitor names/layout and cursor theme if this machine's setup differs (see "Using this on your own machine" above).
- Log out and back in (or reboot) once after the first deploy — group memberships (`docker`, `libvirtd`, `wheel`, `video`, `audio`) only take effect on next login, not immediately after `nixos-rebuild switch`.
- Secrets (`secrets.nix`) won't decrypt on a machine that's never seen the age private key before — see the "Secrets" section below. That needs doing *before* the first `nixos-rebuild switch` that references a `sops.secrets.*` value (currently just ProtonVPN).

### Secrets (`secrets.nix`)
`secrets/secrets.yaml` is encrypted for one age public key (declared in `.sops.yaml`) and is safe to have in a public repo — only the matching private key can decrypt it, and that key never touches this repo. Decryption happens at system activation, so the private key has to already be on disk as `/var/lib/sops-nix/key.txt` (root-only, `0400`) *before* the first rebuild that needs it — Nix can't put it there for you, same reasoning as the old ProtonVPN file used to be manual. On a new machine (or if the key is ever lost): generate a fresh age keypair, install the private half at that path, then re-encrypt `secrets/secrets.yaml` for the new public key with `sops updatekeys` (after updating `.sops.yaml` to match) so the new machine can actually read it.

Editing an existing secret: `sops secrets/secrets.yaml` (needs `SOPS_AGE_KEY_FILE` pointed at the private key, or the key already at its default lookup path) opens it decrypted in `$EDITOR` and re-encrypts on save. The `*.nix` glob in the deploy command doesn't pick up `secrets/secrets.yaml` — see Deploying above for the extra copy step whenever this file changes.

### Amazfit watch (`amazfit.nix`)
1. Pair and sync the watch at least once through the official Zepp mobile app first — `huami-token` can't find a device that's never synced.
2. Run `amazfit-get-key.sh` and type the Zepp account email/password when prompted (password goes straight to `huami-token`, never stored anywhere).
3. Copy the printed auth key into Amazfish: Settings > Device > Auth Key.
4. Repeat 2–3 any time the watch is unpaired and re-paired.

### Spotify (`home.nix`)
- Installed as a user-scope Flatpak so spicetify can patch it — log into Spotify normally on first launch. That first launch is also what creates `~/.var/app/com.spotify.Client/config/spotify/prefs`, which the next step needs to already exist.
- One-time spicetify setup, after that first login (Nix can't do this for me — it's spicetify's own runtime state, not something home-manager writes): `spicetify config current_theme caelestia color_scheme caelestia prefs_path ~/.var/app/com.spotify.Client/config/spotify/prefs`, then `spicetify backup apply`. Skipping this leaves `current_theme`/`color_scheme` blank, so every later `spicetify apply` (including the postHook's) silently re-applies no theme at all — Spotify just never looks themed and nothing complains.
- Live theme sync doesn't work under Flatpak (`spicetify watch` crashes outside its sandbox), so colors only update via a postHook script on scheme change — restart Spotify by hand to actually see the new theme.

### Vesktop (`home.nix`)
- caelestia writes the generated theme to `~/.config/vesktop/themes/caelestia.theme.css` on every scheme change (`enableDiscord` in `home.nix`), but Vencord never auto-enables a theme file just because it exists in that folder — it has to be turned on once, by hand, in Vesktop's Settings > Themes tab. Until then Vesktop just runs unthemed with no indication why.

### VSCodium Caelestia integration
- The extension is installed once from a vendored `.vsix` and then left alone (so it can regenerate its own theme file without Nix stomping it every rebuild) — an actual extension version bump requires manually deleting the installed extension directory first so it reinstalls.

### Docker / Rancher (`dev.nix`)
- Both are deliberately not auto-started, to avoid idle resource usage. Just running any `docker` command starts the daemon on demand; Rancher needs `systemctl start docker-rancher` explicitly.
- First visit to the Rancher GUI (`https://localhost:8443`) will walk through its own first-run admin account setup.

### Windows VM / Dubbing AI (`windows-vm.nix`, `audio-routing.nix`)
- Needs a Windows 10 ISO manually placed at `~/isos/Win10.iso` before the VM can boot for the first time.
- After Windows is installed, I need to install SPICE Guest Tools inside the guest — it's what makes the QXL video device (`windows-vm.nix`) actually work instead of falling back to a slow generic VGA driver, and it's what gives me clipboard sharing and cursor integration via the `spicevmc` channel. Not something Nix can automate since it runs inside the guest.
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
