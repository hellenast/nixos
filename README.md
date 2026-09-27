# nixos

<img width="2560" height="1440" alt="Screenshot_2026-08-17_14-31-32" src="https://github.com/user-attachments/assets/b71220f4-7a07-47f7-8b13-44e40ff8364f" />

My personal NixOS + Hyprland + [caelestia-shell](https://github.com/caelestia-dots/shell) flake config, built to be forkable — everything specific to my machine (username, hostname, locale, monitor layout, cursor theme) lives in one file, `variables.nix`. It's declarative except for a handful of things that genuinely can't be (accounts, pairing, stateful data), all listed in the docs.

## Layout

```
flake.nix            inputs, and wires modules/ + home-manager together
variables.nix        everything machine/user-specific — the one file to edit
fresh-install.sh     from-scratch install from the live ISO
secrets/             sops-encrypted secrets (safe to commit)
modules/
  default.nix        the list of system modules in use
  system/            disk, boot, hardware, users, nix, memory, power, secrets
  desktop/           Hyprland session, audio, caelestia (system side), Thunar, Flatpak
  apps/              dev tooling, Claude Code, Amazfit watch
  gaming/            Steam (+ Millennium theme), Minecraft, Roblox, VR
  virtualisation/    Windows VM + its virtual mic, Waydroid
  network/           ProtonVPN split tunnel, Tor
  home/              home-manager: caelestia, Hyprland config, terminal, apps
docs/
```

## Docs

- [Getting started](docs/getting-started.md) — adapting this repo to your own machine
- [Deploying and updating](docs/deploying.md) — the deploy command, keeping things up to date
- [Installing from scratch](docs/installing.md) — full-disk-encrypted reinstall with disko
- [Modules](docs/modules.md) — what every module does
- [Manual setup](docs/manual-setup.md) — everything `nixos-rebuild` can't do for you
  - [Secrets](docs/secrets.md) — sops-nix and the age key
  - [ProtonVPN](docs/protonvpn.md) — WireGuard config, per-app VPN
  - [Caelestia theming](docs/theming.md) — Spotify, Vesktop, VSCodium, Zen, Helium, ZapZap, Steam
  - [Gaming](docs/gaming.md) — Steam/GameMode, Minecraft (both editions), VR
  - [VMs and containers](docs/virtualisation.md) — Windows VM / Dubbing AI, Waydroid

## Deploying

```
sudo rm -rf /etc/nixos/modules && sudo cp -r ~/nixos/*.nix ~/nixos/modules ~/nixos/secrets /etc/nixos/ && cd /etc/nixos && sudo nixos-rebuild switch --flake .#
```

See [docs/deploying.md](docs/deploying.md) for what this does and doesn't copy.
