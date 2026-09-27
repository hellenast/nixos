#!/usr/bin/env bash
# Makes a USB stick for installing any machine in hosts/ from scratch
# (docs/installing.md). Any stick with room for the ISO and a bit more:
#   partitions 1-2  the installer ISO (boots in UEFI and BIOS mode). By
#                   default the one this repo builds (installer/iso.nix),
#                   which has a `fresh-install` command; --iso writes
#                   another NixOS ISO instead.
#   partition 3     FAT32 "NIXCFG", the rest of the stick: this repo (working
#                   tree and .git) with the age key next to flake.nix, which
#                   fresh-install.sh finds and installs.
#
# Usage: sudo bash prepare-usb.sh [--iso FILE] [--no-key] [--config-only] [DEVICE]
#   DEVICE         the stick, e.g. /dev/sdb (default: asks among USB drives)
#   --iso FILE     write this ISO instead of building the repo's
#   --no-key       leave the age key off the stick
#   --config-only  only refresh NIXCFG (repo and key) on a stick made before
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KEY=/var/lib/sops-nix/key.txt
MIN_CONFIG_MIB=256 # the repo takes a few MiB; FAT32 wants some room anyway

ISO='' WITH_KEY=1 CONFIG_ONLY=0 DEV=''

die() {
    echo "!! $*" >&2
    exit 1
}

while (($#)); do
    case $1 in
        --iso)
            ISO=${2-}
            [[ -f $ISO ]] || die "--iso needs an ISO file."
            ISO=$(realpath "$ISO")
            shift
            ;;
        --no-key) WITH_KEY=0 ;;
        --config-only) CONFIG_ONLY=1 ;;
        -h | --help)
            sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
            exit 0
            ;;
        -*) die "Unknown option $1 (see --help)." ;;
        *) DEV=$1 ;;
    esac
    shift
done
((EUID == 0)) || die "Run it as root: sudo bash prepare-usb.sh"
[[ -f $REPO/flake.nix ]] || die "$REPO doesn't look like the repo."

# --- The stick ---

# USB or removable whole disks: "path<TAB>size model".
candidates() {
    local name type rm tran
    # TRAN last: it's the column that can be empty.
    while read -r name type rm tran; do
        [[ $type == disk && ($tran == usb || $rm == 1) ]] || continue
        case ${name##*/} in zram* | loop* | sr*) continue ;; esac
        printf '%s\t%s\n' "$name" "$(lsblk -dno SIZE,MODEL "$name" | xargs)"
    done < <(lsblk -dnpo NAME,TYPE,RM,TRAN)
}

if [[ -z $DEV ]]; then
    mapfile -t sticks < <(candidates)
    ((${#sticks[@]})) || die "No USB stick found."
    if ((${#sticks[@]} == 1)); then
        choice=1
    else
        for i in "${!sticks[@]}"; do printf '  %d) %s  %s\n' $((i + 1)) "${sticks[i]%%$'\t'*}" "${sticks[i]#*$'\t'}"; done
        read -rp "Which one? " choice
        if [[ ! $choice =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#sticks[@]})); then die "No such stick."; fi
    fi
    DEV=${sticks[choice - 1]%%$'\t'*}
fi
DEV=$(readlink -f "$DEV")
[[ -b $DEV && $(lsblk -dno TYPE "$DEV") == disk ]] || die "$DEV isn't a whole disk."
# Never a disk the running system uses: only mounts where sticks get
# mounted (the desktop's automount, or by hand) are fine.
while read -r mountpoint; do
    [[ -z $mountpoint || $mountpoint =~ ^(/run/media|/media|/mnt)(/|$) ]] ||
        die "$DEV has $mountpoint mounted; refusing."
done < <(lsblk -nro MOUNTPOINT "$DEV")
[[ $(blockdev --getss "$DEV") == 512 ]] || die "$DEV has $(blockdev --getss "$DEV")-byte sectors; the ISO's partition table assumes 512."
DESC="$(lsblk -dno SIZE,MODEL "$DEV" | xargs)"

unmount_all() {
    local mountpoint
    while read -r mountpoint; do
        [[ -z $mountpoint ]] || umount "$(printf '%b' "$mountpoint")"
    done < <(lsblk -nro MOUNTPOINT "$DEV" | sort -r)
}

# Puts the repo and the key on a NIXCFG partition.
copy_config() {
    local part=$1 mnt
    mnt=$(mktemp -d)
    mount "$part" "$mnt"
    # FAT keeps no permissions or symlinks: -rt only, and no `result` links
    # (fresh-install.sh restores the file modes from git). --delete: a
    # refresh leaves no stale files behind.
    rsync -rt --delete --exclude /result --exclude '/result-*' "$REPO"/ "$mnt"/nixos/
    if ((WITH_KEY)); then
        if [[ -f $KEY ]]; then
            cp "$KEY" "$mnt"/nixos/key.txt
            echo "    Age key copied (nixos/key.txt): keep the stick safe."
        else
            echo "!! No $KEY here; the stick goes without the age key." >&2
        fi
    fi
    sync
    echo "    $(du -sh "$mnt"/nixos | cut -f1) of config on NIXCFG."
    umount "$mnt"
    rmdir "$mnt"
}

if ((CONFIG_ONLY)); then
    part=$(lsblk -nrpo NAME,LABEL "$DEV" | awk '$2 == "NIXCFG" { print $1; exit }')
    [[ -n $part ]] || die "$DEV has no NIXCFG partition; make the stick without --config-only first."
    echo "==> Refreshing NIXCFG ($part) on $DEV ($DESC)"
    unmount_all
    copy_config "$part"
    echo "Done."
    exit 0
fi

# --- The ISO ---

if [[ -z $ISO ]]; then
    echo "==> Building the installer ISO from $REPO (the first time: ~75 MiB of downloads, a few minutes)"
    # As the user who ran sudo, like any other build of the repo.
    build=(nix --extra-experimental-features "nix-command flakes" build --no-link --print-out-paths "path:$REPO#installer-iso")
    if [[ -n ${SUDO_USER-} ]]; then out=$(sudo -H -u "$SUDO_USER" "${build[@]}"); else out=$("${build[@]}"); fi
    isos=("${out%%$'\n'*}"/iso/*.iso)
    ISO=${isos[0]}
    [[ -f $ISO ]] || die "The build produced no ISO."
fi
iso_bytes=$(stat -c %s "$ISO")
stick_bytes=$(lsblk -dnbo SIZE "$DEV")
# NIXCFG starts at the first MiB boundary after the ISO and takes the rest.
# shellcheck disable=SC2017 # rounding up to whole MiB is the point
start=$(((iso_bytes + 1048575) / 1048576 * 2048))
config_mib=$(((stick_bytes / 512 - start) / 2048))
((config_mib >= MIN_CONFIG_MIB)) ||
    die "$DEV ($DESC) is too small: the ISO takes $((iso_bytes / 1048576)) MiB and NIXCFG needs at least $MIN_CONFIG_MIB MiB more."

echo
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$DEV"
echo
echo "Will write ${ISO##*/} ($((iso_bytes / 1048576)) MiB), then NIXCFG with the repo$( ((WITH_KEY)) && echo ' and the age key') ($((config_mib / 1024)) GiB)."
read -rp "EVERYTHING ON $DEV ($DESC) WILL BE ERASED. Type YES: " answer
[[ $answer == YES ]] || die "Aborted; nothing written."

echo "==> Unmounting"
unmount_all

echo "==> Writing the ISO"
dd if="$ISO" of="$DEV" bs=4M conv=fsync status=progress
sync

echo "==> Adding NIXCFG after it"
# A stick made before still has the old NIXCFG's filesystem where the new
# one goes (writing the ISO doesn't reach that far): clear its first MiB —
# boot sector and backup — so nothing stale is left for sfdisk to warn about
# or anything to mistake for a filesystem before it's formatted.
dd if=/dev/zero of="$DEV" bs=1M seek=$((start / 2048)) count=1 conv=fsync status=none
echo "start=$start, type=c" | sfdisk --quiet --append --no-reread "$DEV"
partx -u "$DEV" 2>/dev/null || partx -a "$DEV"
udevadm settle
# The new partition: the one starting where it was put (sda3, mmcblk0p3, ...).
part=''
for sys in /sys/class/block/"${DEV##*/}"/"${DEV##*/}"*; do
    if [[ $(cat "$sys/start" 2>/dev/null) == "$start" ]]; then part=/dev/${sys##*/}; fi
done
[[ -b $part ]] || die "The new partition didn't show up; unplug the stick, plug it back in and run: sudo bash $0 --config-only $DEV (after making NIXCFG by hand)."
unmount_all # a desktop may automount the ISO's partitions right away
mkfs.vfat -F 32 -n NIXCFG "$part" >/dev/null

echo "==> Copying the repo"
copy_config "$part"

echo "==> Reading the ISO part back from the stick (all but the partition table, which now lists NIXCFG too)"
# Straight from the stick (iflag=direct): a plain read gets what the kernel
# still holds in memory from writing it, which matches even when the stick
# lost the writes — as failing and fake-capacity sticks do.
blockdev --flushbufs "$DEV"
cmp -i 512 -n $((iso_bytes - 512)) "$ISO" <(dd if="$DEV" bs=4M iflag=direct,count_bytes count="$iso_bytes" status=none) ||
    die "The stick doesn't hold what was written to it: it's likely failing (or not the size it claims). Try another stick."
echo "    Written correctly."

lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
echo
echo "Done. Boot the machine from the stick (UEFI), then run:"
if [[ ${ISO##*/} == nixos-hyena-installer* ]]; then
    echo "  sudo fresh-install"
else
    # A stock ISO has no fresh-install command, and holds the stick's whole
    # disk while running, so NIXCFG only mounts through a loop device.
    name=${part##*/}
    echo "  sudo mount -o ro,loop,offset=$((start * 512)),sizelimit=\$((512 * \$(cat /sys/class/block/$name/size))) /dev/${DEV##*/} /mnt"
    echo "  sudo bash /mnt/nixos/fresh-install.sh"
    echo "(The device names are this machine's; check them with lsblk there.)"
fi
