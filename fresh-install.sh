#!/usr/bin/env bash
# Fresh NixOS install helper — I run this from the live ISO.
#
# What it does:
#   1. Finds a mounted/mountable USB stick containing flake.nix
#   2. Copies it to /root/nixos-config
#   3. Verifies the target NVMe id in disko.nix matches an actual disk here
#   4. Comments out ./secrets.nix, ./protonvpn.nix, and the sops-nix module
#      in the copy (protonvpn.nix hard-references config.sops.secrets, so
#      it can't stay if secrets.nix/sops are disabled — leaving it in would
#      break evaluation) so the install doesn't need the (currently
#      missing) age key
#   5. Runs disko (WIPES THE TARGET DISK — confirmation required)
#   6. Runs nixos-install
#   7. Prompts me to set the user password via nixos-enter
#   8. Copies the (patched) config into /mnt/etc/nixos for after reboot
#
# I re-enable ProtonVPN/secrets after first boot, once I've restored (or
# regenerated — see README.md -> "Secrets") /var/lib/sops-nix/key.txt and
# secrets/secrets.yaml. See README.md -> "Reinstalling with full-disk
# encryption" for the exact re-enable steps.
#
# Usage: sudo bash fresh-install.sh

set -euo pipefail

# Set once, respected by both the `nix` CLI and nixos-install (which
# shells out to `nix build` internally but has its own, more limited,
# arg parser that does NOT understand --extra-experimental-features).
export NIX_CONFIG="extra-experimental-features = nix-command flakes"

FLAKE_TARGET="hyena"                 # matches hostname in variables.nix
CONFIG_DIR="/root/nixos-config"

echo "==> Looking for a USB stick with your flake..."

FOUND=""

# First check partitions that are ALREADY mounted somewhere (e.g. you
# mounted this stick yourself to grab this very script) — mounting them
# again below would just fail silently and skip them.
while read -r dev mp; do
    [ -z "$mp" ] && continue
    if [ -f "$mp/flake.nix" ]; then
        echo "Found flake.nix on already-mounted /dev/$dev at $mp"
        FOUND="$mp"
        break
    fi
done < <(lsblk -rno NAME,MOUNTPOINT | awk '$2!=""')

# Then try mounting anything not yet mounted.
if [ -z "$FOUND" ]; then
    for dev in $(lsblk -rno NAME,TYPE,MOUNTPOINT | awk '$2=="part" && $3==""{print $1}'); do
        mp="/mnt/_scan_$dev"
        mkdir -p "$mp"
        if mount "/dev/$dev" "$mp" 2>/dev/null; then
            if [ -f "$mp/flake.nix" ]; then
                echo "Found flake.nix on /dev/$dev"
                FOUND="$mp"
                break
            fi
            umount "$mp"
        fi
        rmdir "$mp" 2>/dev/null || true
    done
fi

if [ -z "$FOUND" ]; then
    echo "Could not auto-find a USB stick with flake.nix on it."
    echo "Mount it yourself and re-run, or pass its path:"
    echo "  sudo bash fresh-install.sh /path/to/mounted/usb"
    if [ "${1:-}" != "" ] && [ -f "$1/flake.nix" ]; then
        FOUND="$1"
    else
        exit 1
    fi
fi

echo "==> Copying config to $CONFIG_DIR"
rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
cp -r "$FOUND"/* "$CONFIG_DIR"/

echo "==> Checking NVMe id in disko.nix against actual hardware..."
EXPECTED_ID=$(grep -oP '(?<=device = ")[^"]+' "$CONFIG_DIR/disko.nix")
EXPECTED_NAME=$(basename "$EXPECTED_ID")

if [ -e "/dev/disk/by-id/$EXPECTED_NAME" ]; then
    echo "Match found: /dev/disk/by-id/$EXPECTED_NAME"
else
    echo "!! disko.nix expects: $EXPECTED_NAME"
    echo "!! Not found under /dev/disk/by-id/. Actual NVMe disks:"
    lsblk -d -o NAME,SIZE,MODEL,SERIAL | grep -i nvme || true
    echo
    read -rp "Edit $CONFIG_DIR/disko.nix's device line now, then press Enter to continue (or Ctrl+C to abort): "
fi

echo "==> Patching flake.nix: disabling secrets.nix, protonvpn.nix, sops module"
sed -i \
    -e 's|^\( *\)\./secrets\.nix|\1# ./secrets.nix   # disabled by fresh-install.sh: no age key present|' \
    -e 's|^\( *\)\./protonvpn\.nix|\1# ./protonvpn.nix # disabled by fresh-install.sh: depends on sops secrets|' \
    -e 's|^\( *\)inputs\.sops-nix\.nixosModules\.sops|\1# inputs.sops-nix.nixosModules.sops # disabled by fresh-install.sh|' \
    "$CONFIG_DIR/flake.nix"

echo "==> Patched module list:"
grep -n '\./secrets\.nix\|\./protonvpn\.nix\|sops-nix\.nixosModules\.sops' "$CONFIG_DIR/flake.nix"

echo
echo "###########################################################"
echo "# About to run disko against: /dev/disk/by-id/$EXPECTED_NAME"
echo "# THIS WILL DESTROY ALL DATA ON THAT DISK."
echo "###########################################################"
read -rp "Type YES to continue: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

nix run github:nix-community/disko -- \
    --mode disko --flake "$CONFIG_DIR#$FLAKE_TARGET"

echo "==> Installing..."
nixos-install --flake "$CONFIG_DIR#$FLAKE_TARGET" --root /mnt

echo "==> Set your user password now:"
nixos-enter --root /mnt -c "passwd $(grep -oP '(?<=username = ")[^"]+' "$CONFIG_DIR/variables.nix")"

echo "==> Copying patched config into /mnt/etc/nixos for after reboot"
mkdir -p /mnt/etc/nixos
cp -r "$CONFIG_DIR"/* /mnt/etc/nixos/

echo
echo "==> Done. Remember: secrets.nix / protonvpn.nix / sops are DISABLED"
echo "    in the installed config. Re-enable them once you've restored"
echo "    /var/lib/sops-nix/key.txt and re-encrypted secrets/secrets.yaml,"
echo "    then run: sudo nixos-rebuild switch --flake /etc/nixos#$FLAKE_TARGET"
echo
echo "Reboot and remove the USB stick when it does."
