# Manual setup

Things a plain `nixos-rebuild switch` can't do — either because they're interactive (logins, device pairing, 2FA) or because they involve real stateful data Nix deliberately doesn't touch.

Topic pages:
- [Secrets](secrets.md) — the age key, needed before the first rebuild that decrypts anything
- [ProtonVPN](protonvpn.md) — getting and encrypting the WireGuard config
- [Caelestia theming](theming.md) — one-time steps for Spotify, Vesktop, VSCodium, Zen, Helium, ZapZap, Steam
- [Gaming](gaming.md) — GameMode, Minecraft (both editions), VR headset
- [VMs and containers](virtualisation.md) — Windows VM / Dubbing AI, Waydroid

## Every fresh install / new machine

- Regenerate `modules/system/hardware-configuration.nix` for the actual hardware (`nixos-generate-config`).
- Update `variables.nix` — at least `username`/`userDescription`/`hostname`; monitors and cursor theme too if they differ ([getting-started.md](getting-started.md)).
- Put the age private key in place *before* the first rebuild that uses `system/secrets.nix` ([secrets.md](secrets.md)).
- Log out and back in once after the first deploy — group memberships (`docker`, `libvirtd`, `wheel`, `video`, `audio`) only apply at login.

## Amazfit watch (`apps/amazfit.nix`)

1. Pair and sync the watch at least once in the official Zepp phone app — `huami-token` can't find a device that has never synced.
2. Run `amazfit-get-key.sh` and enter the Zepp account email/password when asked (the password goes straight to `huami-token` and isn't stored).
3. Paste the printed auth key into Amazfish: Settings > Device > Auth Key.
4. Repeat 2–3 whenever the watch is unpaired and re-paired.

## Docker / Rancher (`apps/dev.nix`)

- Neither starts at boot, to avoid idle resource use. Any `docker` command starts the daemon on demand; Rancher needs `systemctl start docker-rancher`.
- The first visit to the Rancher GUI (`https://localhost:8443`) walks through its own admin account setup.

## Claude Code (`apps/ai.nix`)

- Log in once with `claude` → `/login`, with a claude.ai account (remote control needs a subscription login, not an API key). After that, `claude rc` in any project directory starts a session that can be picked up from the Claude app or claude.ai/code.

## Bottles (`home/default.nix`)

- Each Windows app (Rave, etc.) needs its own bottle, created in the Bottles GUI, with the app's `.exe` run inside it to install.
- Bottle data (prefixes, installed apps) lives in `~/.local/share/bottles` — covered by backing up `/home`.
