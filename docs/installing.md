# Installing from scratch (full-disk encryption)

My machine was originally installed without disk encryption; `modules/system/disko.nix` describes the encrypted layout it should have going forward (plaintext ESP + one LUKS2 partition holding a btrfs volume). Since LUKS reformats the partition it lives on, getting there means backing up and reinstalling — there's no in-place upgrade. Once done, this only needs repeating if the disk is ever wiped again.

**The age-key wrinkle.** `system/secrets.nix` and `network/protonvpn.nix` need the age private key at `/var/lib/sops-nix/key.txt` to decrypt `secrets/secrets.yaml` ([secrets.md](secrets.md)), and a fresh install doesn't have it. Left enabled without it, `nixos-install` fails during activation. So the key goes on the install stick along with the repo: `fresh-install.sh` finds it and puts it in place before installing. Without it, both modules are left out of the first install and added back afterwards ([Adding the secrets back](#adding-the-secrets-back)).

## Before you start

1. **Back up everything that isn't rebuilt by Nix:**
   - `/home` and `/persist` — real data.
   - `/var/lib/libvirt/images` — the Windows VM disk ([virtualisation.md](virtualisation.md)).
   - `/var/lib/waydroid/data` — Waydroid's Android `/data`: installed apps, their data, signed-in accounts. (`/var/lib/waydroid/images` and `rootfs` aren't worth it — `waydroid init` downloads them again.)
   - `/var/lib/sops-nix/key.txt` — the age private key. Without it, `secrets/secrets.yaml` can't be read after the reinstall and you'll have to generate a new key and re-encrypt ([secrets.md](secrets.md)).

   Copy them somewhere separate, or plan to reinstall Windows / regenerate the key / redo Waydroid apps from scratch.
2. **Make the install stick** (below): the installer ISO, plus this repo and a copy of the age key.
3. Boot the machine from it, in UEFI mode.

## Making the install stick: `prepare-usb.sh`

With the stick plugged into a machine that has this repo (any stick with room for the ~1.5 GB ISO and a bit more; everything on it is erased):

```
sudo bash ~/nixos/prepare-usb.sh
```

It asks which USB drive to use (or takes it as an argument, e.g. `/dev/sdb`), then:

1. Builds the installer ISO from this repo (`nix build .#installer-iso`, from `installer/iso.nix`): NixOS's minimal installer plus a `fresh-install` command, and compressed swap in RAM from boot. The first build downloads ~75 MiB and takes a couple of minutes.
2. Writes it to the start of the stick, and makes the rest of the stick, whatever its size, a FAT32 partition labelled `NIXCFG`.
3. Copies the repo there as it is now (working tree and `.git`, uncommitted changes included), with the age key from `/var/lib/sops-nix/key.txt` next to `flake.nix`. Anyone holding the stick can read the key, so keep it safe; `--no-key` leaves it off.

After changing the repo, `sudo bash prepare-usb.sh --config-only` refreshes just `NIXCFG` — no new ISO needed, since the ISO runs the `fresh-install.sh` it finds there. `--iso FILE` writes a stock NixOS ISO instead of building one (see below for how to start the install from it).

## The easy way: `fresh-install.sh`

Booted from the stick, log in (it logs in automatically as `nixos`) and run:

```
sudo fresh-install
```

That finds the stick's `NIXCFG` partition and runs the `fresh-install.sh` on it (or, on a stick without one, the copy built into the ISO); options go through, e.g. `sudo fresh-install --dry-run`.

**From a stock NixOS ISO** — best avoided on machines with little RAM: the repo's ISO carries disko and every tool the partitioning uses, while a stock one downloads them into its RAM-backed store at that step (hundreds of MiB, compiler included), and can run out of space there. There's no `fresh-install` command either: mount the stick with the repo and run the script from it. With the repo on a separate stick, that's `sudo mount /dev/sdX1 /mnt && sudo bash /mnt/nixos/fresh-install.sh`. With it on a partition of the stick the ISO itself booted from, a plain mount fails with "Can't open blockdev" — the running ISO holds the stick's whole disk — so it has to go through a loop device over the disk, at the partition's offset:

```
sudo mount -o ro,loop,offset=$((512 * $(cat /sys/class/block/sdX3/start))),sizelimit=$((512 * $(cat /sys/class/block/sdX3/size))) /dev/sdX /mnt
sudo bash /mnt/nixos/fresh-install.sh
```

(The script's own search of the sticks, and the `fresh-install` command, do that by themselves.)

It asks everything up front and writes nothing to any disk until you type YES:

1. **Network.** Checks it's online, and offers to join a Wi-Fi network if not (through NetworkManager, which the installer ISO has; `nmtui` works too).
2. **The config.** Mounts every USB stick read-only and searches it for this repo, then the other drives if no stick has it. With more than one copy, it shows each one's last commit (or last change) and asks which. The copy goes to RAM, so the stick can come out afterwards.
3. **The machine.** Lists the machines in `hosts/` ([machines.md](machines.md)) and suggests the one matching the hardware it finds (laptop or not, CPU, GPUs) — or sets up a new one from a copy of another. It asks whether this is a laptop, and brings the machine's `cpu`, `gpus` and NVIDIA bus IDs in line with the hardware.
4. **The keyboard.** On a machine with a non-US keyboard (the laptops' ABNT2), it switches the ISO's console to that keymap, so the passwords and passphrase typed next are the ones the installed system expects. (It can't from a graphical ISO's terminal; then it says to switch the desktop's layout by hand.)
5. **The age key.** Checks every key it came across against the one `secrets/secrets.yaml` is encrypted for, and keeps the match. None: it asks for a path, or goes on without the secrets.
6. **The disk.** Lists every disk with its size, model and current partitions, marks the machine's current `disk`, and asks which to install on. Disks in use, like the live ISO's own stick, can't be picked. The choice becomes the machine's `disk`, as its `/dev/disk/by-id` path.
7. **Hardware.** Runs `nixos-generate-config` for the machine's `hardware-configuration.nix`: written straight away for a new machine or a placeholder (the laptops before their first install), and otherwise, if it differs, after showing the diff and asking.
8. **Modules.** Lists every module in `modules/default.nix` and `modules/home/default.nix`, with its description from [modules.md](modules.md), to toggle by number, starting from what the machine has. Dependencies follow along (leaving out `gaming/steam` leaves out `gaming/vr` too, for instance), and the core ones — boot, disk, GPU, power, the desktop itself — are always installed. The result goes into the machine's `disabledModules`.
9. **Passwords** for your user and root (the same, by default).
10. **Evaluation.** Evaluates the whole configuration, so a module combination that doesn't work shows up before anything is wiped.

Then a summary, and it asks you to type YES. From there, the only thing left to type is the LUKS passphrase: disko partitions, encrypts and mounts the disk, asking for it twice — pick one you're happy typing on every boot. Then it installs the age key, runs `nixos-install` — several GiB of downloads plus a few packages built from source (the caelestia shell, quickshell, Millennium), so on a laptop allow an hour or more; Nix's status line keeps moving, Alt+F2 opens another console to look around, and on machines with under 16 GB of RAM it builds fewer things at once — sets the passwords, and:

- puts the deploy copy the system was built from in `/etc/nixos` ([deploying.md](deploying.md)), `flake.lock` included;
- puts the whole repo in `~/nixos`, where `git status` and `git diff` show exactly what it changed (the machine's variables and hardware config, or a whole new machine) — commit or revert as you like;
- carries over network connections made in the ISO, and makes the new install the next boot, so a stick left in doesn't boot the ISO again.

It offers to reboot at the end.

`sudo bash fresh-install.sh --help` lists the options: `--dry-run` goes through all of the above and stops before touching any disk (it also works without root on an installed system, to try a change to the repo); `--host`, `--disk` and `--age-key` answer those questions up front; `--resume` carries on with an install stopped after the disk was set up (in the same live session, no questions or wipe); and a path or git URL instead of searching the sticks.

After the first boot, restore `/home`, `/persist`, and (if kept) the Windows VM disk and Waydroid's data. For Waydroid, the order matters: run `sudo waydroid init -s GAPPS` first so `/var/lib/waydroid` exists, stop it (`sudo systemctl stop waydroid-container`), then put the backed-up `data` directory into `/var/lib/waydroid/` before starting a session. That's what brings apps and accounts back instead of a blank Android.

### Adding the secrets back

Only needed if it installed without the age key:

1. Restore `/var/lib/sops-nix/key.txt` from the backup (or generate a new keypair and re-encrypt — [secrets.md](secrets.md)).
2. Remove `"system/secrets.nix"` and `"network/protonvpn.nix"` from the machine's `disabledModules`, in `~/nixos/hosts/<name>/variables.nix`.
3. Deploy ([deploying.md](deploying.md)).

## The manual way

Same result, one step at a time — useful to see or adjust each step, or when the script doesn't fit.

1. Clone the repo in the live environment: `nix-shell -p git --run "git clone <this repo's url> ~/nixos"`.
2. Check the machine's `hosts/<name>/variables.nix` ([machines.md](machines.md)): its `disk` against `ls /dev/disk/by-id/`, its `gpus` (and for NVIDIA PRIME, `gpuBusIds`) against `lspci -D`. A laptop's `hardware-configuration.nix` is a placeholder until generated: `nixos-generate-config --show-hardware-config --no-filesystems > ~/nixos/hosts/<name>/hardware-configuration.nix`.
3. Partition, LUKS-format, create the btrfs subvolumes and mount everything at `/mnt`, in one step, with the disko version pinned in `flake.lock`:
   ```
   sudo nix run --inputs-from ~/nixos disko -- --mode destroy,format,mount --flake ~/nixos#<hostname>
   ```
   It asks for the LUKS passphrase twice — pick one you're happy typing on every boot. On a machine with a non-US `consoleKeyMap` (the laptops' `br-abnt2`), run `sudo loadkeys <that keymap>` first: the initrd reads the passphrase with it (`modules/system/base.nix`), and the passwords typed later should match too.
4. If you have the old age key, restore it now so secrets decrypt on first boot: `sudo install -D -m 0400 -o root -g root <age-key-file> /mnt/var/lib/sops-nix/key.txt`. If not, add `"system/secrets.nix"` and `"network/protonvpn.nix"` to the machine's `disabledModules` (what `fresh-install.sh` does too) and add them back after the first boot ([Adding the secrets back](#adding-the-secrets-back)).
5. Copy the config into place — the normal deploy copy ([deploying.md](deploying.md)), rooted at `/mnt`:
   ```
   sudo mkdir -p /mnt/etc/nixos && sudo cp -r ~/nixos/*.nix ~/nixos/modules ~/nixos/hosts ~/nixos/secrets /mnt/etc/nixos/
   ```
6. Install:
   ```
   sudo nixos-install --root /mnt --flake /mnt/etc/nixos#<hostname>
   ```
   It asks for a root password — anything works; it's a fallback console login, not what's used day to day (greetd logs straight into Hyprland).
7. Reboot and remove the USB stick. The firmware boots the plaintext ESP, systemd-boot loads the kernel/initrd, and the initrd asks for the LUKS passphrase before anything else starts.
8. Restore the backups, as after the easy way (including the Waydroid order).

No `cryptsetup`/`mkfs`/subvolume/`mount` commands anywhere: `disko.nix` is the single source of truth for the disk layout, the way the variables files are for identity, hardware and preferences.
