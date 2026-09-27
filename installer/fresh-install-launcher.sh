# `fresh-install` on the installer ISO (installer/iso.nix): runs the
# fresh-install.sh on the stick's NIXCFG partition — the repo's latest, which
# `prepare-usb.sh --config-only` refreshes without a new ISO — or, without
# one, the copy built into the ISO. Arguments go through to it.

if ((EUID != 0)); then exec sudo "$0" "$@"; fi

config=/run/nixcfg
if ! mountpoint -q "$config" && dev=$(blkid -L NIXCFG); then
    mkdir -p "$config"
    if ! mount -o ro "$dev" "$config" 2>/dev/null; then
        # The ISO holds the stick's whole disk while it runs, so the kernel
        # won't open a partition of it; a loop device over the whole disk,
        # at the partition's offset, reads it anyway (sysfs counts 512-byte
        # sectors).
        name=${dev##*/}
        disk=$(basename "$(readlink -f "/sys/class/block/$name/..")")
        start=$(<"/sys/class/block/$name/start")
        size=$(<"/sys/class/block/$name/size")
        mount -o "ro,loop,offset=$((start * 512)),sizelimit=$((size * 512))" "/dev/$disk" "$config" || rmdir "$config"
    fi
fi

script=$(find "$config" -maxdepth 3 -name fresh-install.sh -print -quit 2>/dev/null) || true
if [[ -n $script ]]; then
    echo "Running $script, from the stick's NIXCFG partition."
    exec bash "$script" "$@"
fi
echo "No NIXCFG partition with fresh-install.sh on it; running the copy built into this ISO."
exec bash @builtin@ "$@"
