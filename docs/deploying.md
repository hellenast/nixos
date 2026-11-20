# Deploying and updating

## Deploying

The repo lives in `~/nixos`; the system is built from a copy in `/etc/nixos`:

```
sudo rm -rf /etc/nixos/modules /etc/nixos/hosts && sudo cp -r ~/nixos/*.nix ~/nixos/flake.lock ~/nixos/modules ~/nixos/hosts ~/nixos/secrets /etc/nixos/ && cd /etc/nixos && sudo nixos-rebuild switch --flake .#
```

- `*.nix` picks up `flake.nix` and `variables.nix`; `flake.lock` is named on its own; `modules/`, `hosts/` and `secrets/` are copied whole. `secrets/secrets.yaml` is encrypted, so copying it around is fine ([secrets.md](secrets.md)).
- `/etc/nixos/modules` and `/etc/nixos/hosts` are cleared first so a module or machine deleted or renamed in the repo doesn't linger there.
- **`flake.lock` is copied too**, so `/etc/nixos` builds exactly the input versions locked in `~/nixos` — the ones reviewed with `update-flake.sh` (below). Leaving it out makes the rebuild use whatever lock `/etc/nixos` already has: input updates silently don't happen, and module changes that depend on them fail to build.
- `nixos-rebuild switch --flake .#` (no name after `#`) builds the `nixosConfigurations` entry matching the machine's actual hostname: its folder in `hosts/` ([machines.md](machines.md)). The same command works on every machine.

After the first deploy on a new machine, log out and back in once: group memberships (`docker`, `libvirtd`, `wheel`, ...) only take effect on the next login.

### Moving from the old flat layout

Deploys from before the `modules/` restructure left top-level module files in `/etc/nixos` (`configuration.nix`, `home.nix`, `gaming.nix`, ...). Nothing imports them anymore, so they're harmless, but they can be removed once:

```
cd /etc/nixos && sudo rm -f ai.nix amazfit.nix audio-routing.nix caelestia-system.nix configuration.nix dev.nix disko.nix firmware.nix gaming.nix hardware-configuration.nix home.nix media.nix oom.nix protonvpn.nix secrets.nix tor.nix vr.nix waydroid.nix windows-vm.nix PROTON-VPN-WIREGUARD.md
```

## Staying updated

**Flatpaks update themselves** via nix-flatpak's timers — no action needed:
- System-wide apps (Sober, Amazfish): daily, plus a catch-up on every boot (`modules/desktop/flatpak.nix`). Sober refuses to launch on a stale build, hence the frequency.
- Spotify (user-scope): weekly (`modules/home/apps/spotify.nix`). An update undoes spicetify's patch until the next `spicetify apply`, which runs on every scheme change — if Spotify looks unthemed right after an update, change the wallpaper once or run `spicetify apply`.

**Everything else** (nixpkgs, home-manager, caelestia-shell/cli, browsers, NixVirt, ...) is pinned in `flake.lock` and does *not* update on its own — a bad bump is worth reviewing, and deploying needs `sudo` anyway. `update-flake.sh` (installed to `~/.local/bin`) runs `nix flake update` in `~/nixos` and shows the `flake.lock` diff; deploy afterwards once it looks fine.

**Manually pinned sources** move only when their rev/hash is edited by hand, after reading the new version — `nix flake update` leaves them alone, because the rev is in the `.nix` file itself rather than only in `flake.lock`: Millennium (`flake.nix` input URL), the Steam Material theme (`modules/gaming/steam.nix`), CaelestiaZen (`modules/home/apps/zen.nix`).

**Firmware**: `fwupdmgr refresh && fwupdmgr update`, by hand (`modules/system/hardware.nix`).

Old generations are garbage-collected daily, keeping a week's worth (`modules/system/nix.nix`).
