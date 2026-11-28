# Self-hosted Beeper bridges

`apps/beeper-bridges.nix` runs, for the Beeper account:

- **Beeper's bridges** (`apps/beeper-bridges/bridges.nix`): WhatsApp, Discord (two, one per account), LinkedIn and Signal. Beeper's own bridge software, running here instead of on Beeper's servers. Accounts connected through self-hosted bridges **don't count against Beeper's account limit** (Free: 1 per network, 5 total), so they work on the free plan, and they show up in the Beeper apps like any other.
- **Voice message transcription** (`apps/beeper-bridges/transcriber.nix`, `apps/beeper-bridges/pkgs/beeper-transcriber`): every new voice message, sent or received, goes through Whisper (large-v3-turbo, run locally by whisper.cpp), and the text appears under the message in every Beeper app — the same place Beeper Plus's transcription puts it, since it's stored the same way. The audio never leaves the machine.

Nothing listens on the network: the bridges and the transcriber connect out to Beeper.

**One machine at a time.** Two copies of a bridge would fight over the same accounts. For now it's the desktop (the laptops have the module in `disabledModules`); the plan is an always-on Oracle Cloud VM ([below](#the-cloud-server-hyena-cloud)). While the desktop is off, new messages wait on their networks and arrive once it's back; the Beeper apps keep working with what's already synced.

## Setting it up

After deploying ([deploying.md](deploying.md)), once:

1. **Bridges**: log them in to the Beeper account (email, then the emailed code), which also starts them:
   ```
   sudo beeper-bbctl login
   ```
   `sudo beeper-bbctl whoami` lists them and their state.
2. **Transcriber**:
   ```
   sudo beeper-transcriber-login
   ```
   It asks for the Beeper email, the emailed code, and the account's **recovery code** (Beeper Settings → Security). The recovery code verifies the transcriber's device, which the bridges require before they share message keys with it — without it, voice messages stay encrypted to it.

Both are services from then on, started at boot.

## Bridges

1. Log each account in through its bridge (Settings → Bridges lists them):
   - **WhatsApp, Signal, LinkedIn** (bridgev2): Beeper's usual Connect screen, from the bridge's entry there.
   - **Discord, both accounts** (an older bridge; the Connect screen fails with "Bridge does not support bridgev2 logins"): start a chat from the Beeper (Matrix) account with the bridge's bot — `@sh-discordbot:beeper.local` or `@sh-discord2bot:beeper.local` — and send `login`, which answers with a QR code for the Discord phone app (Settings → Scan QR Code). If Discord then refuses with `captcha-required` (it often does for a new IP), log in with the session token instead: in a browser's private window logged into Discord, F12 → Network → any `discord.com/api` request → copy the `authorization` request header, then send `login-token user <token>` to the bot (it deletes that message itself). Close the browser window without logging out, which would invalidate the token. `help` lists the rest.
   - **Google Chat** isn't here: its bridge hasn't had a release since July 2024 and no longer syncs chats, so that account stays on Beeper's own servers. With every other account self-hosted, it's the only one counting against the free plan's limit.
2. **Moving an account off Beeper's servers**: log it in through the self-hosted bridge first (self-hosted accounts don't count against the limit, so there's room), check its chats came through, *then* remove the Beeper-hosted one in Beeper's Settings → Accounts.

The two bridges' chats don't merge: the self-hosted bridge makes its own, so while both are logged in every conversation shows up twice, and removing the Beeper-hosted account takes its copies away. The new chats fill in from each network's own history, not from Beeper's: Discord has everything; WhatsApp gets what the phone sends to a new linked device (usually months to about a year, old media may be missing); LinkedIn part of it; Signal only messages from the moment it's linked. Check a chat's history came through before removing the old account.

- Logs: `journalctl -u beeper-bridge-sh-whatsapp` (and so on). Bridge data, including each network's session, is in `/var/lib/beeper-bridges`.
- Updates: the bridges come from nixpkgs and update with it (`update-flake.sh`); bbctl and the LinkedIn bridge are pinned in `apps/beeper-bridges/pkgs/` and bumped by hand.
- This relies on Beeper's self-hosting policy ([developers.beeper.com/bridges/self-hosting](https://developers.beeper.com/bridges/self-hosting/)). If Beeper ever drops it, the same bridges run against a self-hosted Matrix server instead, with an open client (Element, SchildiChat, ...).

## Transcriber

`journalctl -fu beeper-transcriber` shows each transcription and how long it took.

- Voice messages only (not other audio files), sent and received, up to 10 minutes — including ones that arrive as an edit: when WhatsApp delivers a message the bridge can't decrypt yet ("Unavailable message" in its log), the bridge posts a placeholder and edits it into the voice message once the phone resends it. Live, it skips ones more than 6 hours old (history a bridge backfills when an account is added). **After downtime** (a reboot, the machine off overnight) it catches up at startup on everything since it last ran, up to 7 days. All adjustable in `transcriber.nix` (`TRANSCRIBE_*` variables, see `pkgs/beeper-transcriber/main.go`).
- **Beeper drops transcripts that reach an app before the voice message itself** — when an app catches up after being closed, or a phone is opened hours later, both arrive in the same sync and Beeper's logs say `is not synced yet, dropping`. So when a chat is read (a read receipt from the account), the transcriber sends that chat's recent transcripts again: by then the reading app has the voice messages, and they attach. Each transcript is repeated at most 3 times, 10 minutes apart at least, for 3 days (`resend.go`).
- **Whisper**: on a machine with a GPU (`gpus` in its variables), whisper.cpp runs on it through Vulkan with the full-precision model — an 8-second voice message takes about 0.6 s on the desktop's RX 9060 XT, and the model keeps ~1.6 GB of video memory while the service runs. Without one (the cloud server), it's the 8-bit model on the CPU, one message at a time; if that's too slow, `whisperModel` in `transcriber.nix` has a faster option.
- It works on Beeper's free plan: Beeper shows any transcript attached to a voice message, Plus or not (only its own Transcribe button is Plus-only). It relies on how Beeper stores transcripts, read from Beeper Desktop 4.3's code rather than a documented API — if a Beeper update stops showing them, that's the place to look.
- **By hand**: `sudo beeper-transcriber-backfill 7d` goes over every voice message of the last 7 days (or `2d`, `12h`, ...): it transcribes the ones without a transcript and sends the existing ones again, which also replaces their Transcribe button, and prints what it found (including audio it skips, and why). It can only reach messages from after the transcriber's login: older ones are encrypted with keys it never received.
- The transcriber appears in Beeper's device list as "beeper-transcriber". Removing it there revokes it; log in again to restore it.

## The cloud server (`hyena-cloud`)

An Oracle Cloud Always Free VM (2 ARM cores, 12 GB), so the bridges don't depend on the desktop being on. Its config is `server/`: a separate `nixosConfigurations.hyena-cloud` in `flake.nix`, sharing none of the desktop/laptop modules except the two parts above.

### Creating the VM

1. Sign up at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/) (a card for identity checks; Always Free stays free unless the account is upgraded). **Home region**: São Paulo — free resources only exist there, and it can't be changed.
2. An SSH key on the desktop (`ssh-keygen -t ed25519`); its `.pub` goes in `sshAuthorizedKeys` in `server/variables.nix`.
3. **The network first**: Networking → Virtual cloud networks → Actions → **Start VCN Wizard → Create VCN with Internet Connectivity**, defaults. (Creating it from the instance form leaves the public IP option disabled.)
4. **Create instance**: shape first (**Ampere → VM.Standard.A1.Flex, 2 OCPUs, 12 GB**), then image (**Canonical Ubuntu**, 24.04 or newer); Shielded instance / Secure Boot **off** (NixOS's boot loader isn't signed for it); the VCN's **public** subnet with **Automatically assign public IPv4 address** on; the SSH public key; a 100 GB boot volume.
5. **"Out of host capacity"** is common, and São Paulo has a single availability domain. **Save as stack** on the instance form keeps the setup; with an API key (Profile → My profile → API keys, configured in `~/.oci/config`), `oci compute instance launch` with the same settings can be retried every few minutes until it goes through. 1 OCPU / 6 GB gets through more easily and can be resized later (stop, Edit → Shape). Delete the API key once the VM exists.

**Idle reclamation**: Oracle stops Always Free VMs that look unused (CPU, network and memory all under 20% for 7 days), and a bridge server is very quiet. It emails first, and Start in the console brings the VM back as it was. Upgrading the account to Pay As You Go ends this (and reportedly restores the old 4 OCPU / 24 GB allowance at no cost), at the price of paid resources being possible: set a budget alert.

### Installing NixOS on it

From `~/nixos`, with the VM's public IP as `$IP` (`path:` so files not yet in git are included):

1. Check the disk matches `disk` in `server/variables.nix` (`/dev/sda` on A1): `ssh ubuntu@$IP lsblk`.
2. Install — this wipes Ubuntu (`server/disko.nix`), builds the system on the VM itself, and reboots into NixOS:
   ```
   nix run github:nix-community/nixos-anywhere -- --flake path:.#hyena-cloud --target-host ubuntu@$IP --build-on remote
   ```
3. From then on it's `root@$IP`. SSH will complain once that the host key changed: `ssh-keygen -R $IP`.

Deploying changes, building on the server (the desktop can't build ARM binaries):

```
nixos-rebuild switch --flake path:$HOME/nixos#hyena-cloud --target-host root@$IP --build-host root@$IP
```

### Moving over from the desktop

The bridges' sessions and the transcriber's login move with their data, so nothing has to be logged in again:

1. On the desktop: `sudo systemctl stop beeper-bridges.target beeper-transcriber whisper-server`.
2. Copy `/var/lib/beeper-bridges` and `/var/lib/beeper-transcriber` to the same paths on the server (e.g. `sudo rsync -a /var/lib/beeper-bridges /var/lib/beeper-transcriber root@$IP:/var/lib/`), then on the server `chown -R beeper-bridges:beeper-bridges /var/lib/beeper-bridges && chown -R beeper-transcriber:beeper-transcriber /var/lib/beeper-transcriber` (user IDs differ between machines) and `systemctl restart beeper-bridges.target beeper-transcriber`.
3. Add `"apps/beeper-bridges.nix"` to the desktop's `disabledModules` (`hosts/hyena/variables.nix`) and deploy the desktop, so its copy never starts again.
