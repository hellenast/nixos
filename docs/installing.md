# Installing from scratch (full-disk encryption)

My machine was originally installed without disk encryption; `modules/system/disko.nix` describes the encrypted layout it should have going forward (plaintext ESP + one LUKS2 partition holding a btrfs volume). Since LUKS reformats the partition it lives on, getting there means backing up and reinstalling — there's no in-place upgrade. Once done, this only needs repeating if the disk is ever wiped again.

**The age-key wrinkle.** `system/secrets.nix` and `network/protonvpn.nix` need the age private key at `/var/lib/sops-nix/key.txt` to decrypt `secrets/secrets.yaml` ([secrets.md](secrets.md)), and a fresh install doesn't have it. Left enabled, `nixos-install` fails during activation. Both paths below handle this by disabling those two modules for the first install and re-enabling them afterwards.

## Before you start

1. **Back up everything that isn't rebuilt by Nix:**
   - `/home` and `/persist` — real data.
   - `/var/lib/libvirt/images` — the Windows VM disk ([virtualisation.md](virtualisation.md)).
   - `/var/lib/waydroid/data` — Waydroid's Android `/data`: installed apps, their data, signed-in accounts. (`/var/lib/waydroid/images` and `rootfs` aren't worth it — `waydroid init` downloads them again.)
   - `/var/lib/sops-nix/key.txt` — the age private key. Without it, `secrets/secrets.yaml` can't be read after the reinstall and you'll have to generate a new key and re-encrypt ([secrets.md](secrets.md)).

   Copy them somewhere separate, or plan to reinstall Windows / regenerate the key / redo Waydroid apps from scratch.
2. Boot the machine from a [NixOS live ISO](https://nixos.org/download) with network access.

## The easy way: `fresh-install.sh`

The script does everything from here: it finds a USB stick with this repo on it, copies it to `/root/nixos-config`, checks the disk id in `modules/system/disko.nix` against the actual hardware (prompting you to fix it if it's drifted), comments out `./system/secrets.nix` and `./network/protonvpn.nix` in that copy's `modules/default.nix`, runs disko and `nixos-install`, prompts for the user password, and copies the patched config into `/mnt/etc/nixos`.

```
sudo bash fresh-install.sh
```

It asks for confirmation before wiping the disk. After it finishes and you've rebooted:

1. Restore `/var/lib/sops-nix/key.txt` from the backup (or generate a new keypair and re-encrypt — [secrets.md](secrets.md)).
2. Uncomment `./system/secrets.nix` and `./network/protonvpn.nix` in `/etc/nixos/modules/default.nix`.
3. `sudo nixos-rebuild switch --flake /etc/nixos#hyena`.
4. Restore `/home`, `/persist`, and (if kept) the Windows VM disk and Waydroid's data. For Waydroid, the order matters: run `sudo waydroid init -s GAPPS` first so `/var/lib/waydroid` exists, stop it (`sudo systemctl stop waydroid-container`), then put the backed-up `data` directory into `/var/lib/waydroid/` before starting a session. That's what brings apps and accounts back instead of a blank Android.

## The manual way

Same result, one step at a time — useful to see or adjust each step, or when the script doesn't fit (different disk, different flake target).

1. Clone the repo in the live environment: `nix-shell -p git --run "git clone <this repo's url> ~/nixos"`.
2. Check that the disk id in `modules/system/disko.nix` is still right: `ls /dev/disk/by-id/ | grep nvme`, compared against its `device` line. Fix it first if it changed.
3. Partition, LUKS-format, create the btrfs subvolumes and mount everything at `/mnt`, in one step:
   ```
   sudo nix run github:nix-community/disko -- --mode disko --flake ~/nixos#<hostname>
   ```
   It asks for the LUKS passphrase twice — pick one you're happy typing on every boot.
4. If you have the old age key, restore it now so secrets decrypt on first boot: `sudo install -D -m 0400 -o root -g root <age-key-file> /mnt/var/lib/sops-nix/key.txt`. If not, comment out `./system/secrets.nix` and `./network/protonvpn.nix` in `~/nixos/modules/default.nix` (the same patch `fresh-install.sh` applies) and re-enable them after first boot, as in the easy way above.
5. Copy the config into place — the normal deploy copy ([deploying.md](deploying.md)), rooted at `/mnt`:
   ```
   sudo mkdir -p /mnt/etc/nixos && sudo cp -r ~/nixos/*.nix ~/nixos/modules ~/nixos/secrets /mnt/etc/nixos/
   ```
6. Install:
   ```
   sudo nixos-install --root /mnt --flake /mnt/etc/nixos#<hostname>
   ```
   It asks for a root password — anything works; it's a fallback console login, not what's used day to day (greetd logs straight into Hyprland).
7. Reboot and remove the USB stick. The firmware boots the plaintext ESP, systemd-boot loads the kernel/initrd, and the initrd asks for the LUKS passphrase before anything else starts.
8. Restore the backups, as in step 4 of the easy way (including the Waydroid order).

No `cryptsetup`/`mkfs`/subvolume/`mount` commands anywhere: `disko.nix` is the single source of truth for the disk layout, the way `variables.nix` is for identity and preferences.
