# nixos

<img width="2560" height="1440" alt="Screenshot_2026-08-17_14-31-32" src="https://github.com/user-attachments/assets/b71220f4-7a07-47f7-8b13-44e40ff8364f" />

My personal NixOS + Hyprland + [caelestia-shell](https://github.com/caelestia-dots/shell) flake config for three machines — a desktop and two laptops — built to be forkable: what they share (username, locale, cursor theme) lives in `variables.nix`, and what makes each one different (laptop or not, GPUs, keyboard, monitors, modules left out) in its own `hosts/<name>/variables.nix`. It's declarative except for a handful of things that genuinely can't be (accounts, pairing, stateful data), all listed in the docs.

## Layout

```
flake.nix            inputs, and one configuration per machine in hosts/
variables.nix        what every machine shares: user, locale, cursor
hosts/<name>/        each machine: its variables.nix and hardware-configuration.nix
prepare-usb.sh       makes the install stick: installer ISO + this repo + the age key
fresh-install.sh     from-scratch install, run from that stick (`sudo fresh-install`)
installer/           the installer ISO (nix build .#installer-iso)
secrets/             sops-encrypted secrets (safe to commit)
modules/
  default.nix        the list of system modules
  system/            disk, boot, GPU, hardware, users, nix, memory, power, secrets
  desktop/           Hyprland session, audio, caelestia (system side), Thunar, Flatpak
  apps/              dev tooling, Claude Code, Amazfit watch
  gaming/            Steam (+ Millennium theme), Minecraft, Roblox, VR
  virtualisation/    Windows VM + its virtual mic, Waydroid
  network/           ProtonVPN split tunnel, Tor
  home/              home-manager: caelestia, Hyprland config, terminal, apps
docs/
```

## Docs

- [Getting started](docs/getting-started.md) — adapting this repo to your own machines
- [Machines](docs/machines.md) — the desktop and the laptops, and what each machine's variables do
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
sudo rm -rf /etc/nixos/modules /etc/nixos/hosts && sudo cp -r ~/nixos/*.nix ~/nixos/modules ~/nixos/hosts ~/nixos/secrets /etc/nixos/ && cd /etc/nixos && sudo nixos-rebuild switch --flake .#
```

See [docs/deploying.md](docs/deploying.md) for what this does and doesn't copy.
