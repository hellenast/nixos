#!/usr/bin/env bash
# Fresh NixOS install from the live ISO, as unattended as it can be: every
# question comes first, and after the wipe confirmation the only thing left
# to type is the LUKS passphrase.
#
# What it does, in order:
#   1. Checks the ISO was booted in UEFI mode (boot.nix uses systemd-boot)
#      and is online, offering to join a Wi-Fi network through nmcli if not.
#   2. Looks for this repo (flake.nix next to variables.nix, modules/ and
#      hosts/, up to 4 folders deep) on every USB stick, mounting each
#      filesystem read-only, then on the other drives if the sticks have
#      none. Age private keys get collected on the way. With more than one
#      copy it asks which, showing each one's last commit or change. The
#      chosen copy goes to RAM, so the stick can come out after.
#   3. Asks which machine in hosts/ this is, suggesting the one whose
#      hardware matches (laptop or not, CPU, GPUs) — or sets up a new one,
#      starting from a copy of another. Asks whether it's a laptop, and
#      brings the machine's cpu, gpus and NVIDIA PRIME bus IDs in line with
#      what's actually there.
#   4. Switches the ISO's keyboard to the machine's keymap (the laptops'
#      ABNT2), so passwords typed here are the ones it'll expect.
#   5. Checks the age keys against the recipient in secrets/secrets.yaml. A
#      match is installed to /var/lib/sops-nix/key.txt before nixos-install,
#      so system/secrets.nix and network/protonvpn.nix work from the first
#      boot. No match: both are left out of this install (docs/installing.md
#      has how to add them back).
#   6. Lists every disk and asks which one to install on, then sets the
#      machine's `disk` to its /dev/disk/by-id path.
#   7. Detects the hardware with nixos-generate-config and writes the
#      machine's hardware-configuration.nix: straight away for a new machine
#      or a placeholder, after showing the diff otherwise.
#   8. Asks which modules to install, keeping the dependencies between them
#      consistent, and writes the machine's disabledModules.
#   9. Asks for the user's password, and root's (the same, by default).
#  10. Evaluates the whole configuration before touching the disk, so a
#      module combination that doesn't work is caught while nothing is lost.
#  11. After a typed confirmation: disko (asks for the LUKS passphrase), the
#      age key, nixos-install, the passwords.
#  12. Copies the config to /etc/nixos (the deploy copy, docs/deploying.md)
#      and the whole repo, .git included if the stick had it, to ~/nixos,
#      where `git status`/`git diff` show what this script changed. Carries
#      over network connections made in the ISO, makes the new install the
#      next boot, and offers to reboot.
#
# Usage: sudo bash fresh-install.sh [--dry-run] [--host NAME] [--disk DEVICE] [--age-key FILE] [SOURCE]
# (--help explains them). docs/installing.md covers the whole reinstall.

set -euo pipefail
shopt -s nullglob

# Set once, respected by both the `nix` CLI and nixos-install (which
# shells out to `nix build` internally but has its own, more limited,
# arg parser that does NOT understand --extra-experimental-features).
#
# The timeouts: a download that stalls fails (and is retried) after a
# minute, instead of leaving the evaluation or the install waiting on it
# for good with nothing on screen.
export NIX_CONFIG="extra-experimental-features = nix-command flakes
connect-timeout = 20
stalled-download-timeout = 60"

# The same for git, which Nix runs for git inputs (Quickshell, through
# caelestia-shell) and builtins.fetchGit: give up on a connection slower
# than 1 KB/s for a minute, and never wait for credentials — a prompt
# nobody can see would hang it too.
export GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60

# --- Module rules (paths relative to modules/) ---

# Always installed, so not offered in the module picker: without them the
# system doesn't build or boot, or the rest of the config falls apart
# (other modules use options defined in home/caelestia.nix, for one).
REQUIRED_MODULES=(
    system/disko.nix system/boot.nix system/gpu.nix system/base.nix
    system/nix.nix system/power.nix
    desktop/session.nix desktop/caelestia.nix
    home/caelestia.nix home/hyprland.nix home/terminal.nix
)

# "A needs B": the picker switches B on along with A, and A off along with
# B. Mirrors the notes in modules/default.nix; keep the two in step.
declare -gA MODULE_NEEDS=(
    [network/protonvpn.nix]="system/secrets.nix"  # reads config.sops.secrets
    [apps/amazfit.nix]="desktop/flatpak.nix"      # a Flatpak app
    [gaming/roblox.nix]="desktop/flatpak.nix"     # a Flatpak app
    [home/apps/spotify.nix]="desktop/flatpak.nix" # user-scope Flatpak still needs the system service
    [gaming/vr.nix]="gaming/steam.nix"            # ALVR streams SteamVR
    [virtualisation/windows-vm.nix]="virtualisation/audio-routing.nix"
    [virtualisation/audio-routing.nix]="virtualisation/windows-vm.nix desktop/audio.nix"
    [network/tor.nix]="home/apps/vesktop.nix"     # its launcher is "Vesktop (Tor)"
)

# Where disko mounts the new system (its default root mountpoint), and
# so where everything is installed.
TARGET=/mnt

# Decrypts secrets/secrets.yaml during activation, so it can only be
# installed with the age key in place.
SECRETS_MODULE=system/secrets.nix

# --- Output and prompts ---

if [[ -t 1 ]]; then
    BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' BLUE=$'\e[34m' RESET=$'\e[0m'
else
    BOLD='' DIM='' RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

step() { printf '\n%s==> %s%s\n' "$BOLD$BLUE" "$*" "$RESET"; }
info() { printf '    %s\n' "$*"; }
ok() { printf '    %s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s!!  %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
die() {
    printf '%s!!  %s%s\n' "$RED" "$*" "$RESET" >&2
    exit 1
}

# ask PROMPT [DEFAULT] — prints the answer (DEFAULT if empty).
ask() {
    local prompt=$1 default=${2-} reply
    [[ -z $default ]] || prompt+=" [$default]"
    read -rp "$prompt: " reply || die "No input, aborting."
    printf '%s\n' "${reply:-$default}"
}

# confirm PROMPT [y|n] — a yes/no question; succeeds on yes.
confirm() {
    local prompt=$1 default=${2:-y} reply hint='[Y/n]'
    [[ $default == y ]] || hint='[y/N]'
    while true; do
        read -rp "$prompt $hint " reply || die "No input, aborting."
        case ${reply:-$default} in
            [Yy] | [Yy][Ee][Ss]) return 0 ;;
            [Nn] | [Nn][Oo]) return 1 ;;
        esac
    done
}

# choose COUNT [DEFAULT] — prints a number from 1 to COUNT.
choose() {
    local count=$1 default=${2-} reply
    while true; do
        reply=$(ask "Choice (1-$count)" "$default")
        if [[ $reply =~ ^[0-9]+$ ]] && ((10#$reply >= 1 && 10#$reply <= count)); then
            printf '%s\n' "$((10#$reply))"
            return 0
        fi
        warn "Enter a number from 1 to $count."
    done
}

# new_password PROMPT — asks twice, prints the yescrypt hash.
new_password() {
    local first second
    while true; do
        read -rsp "$1: " first || die "No input, aborting."
        printf '\n' >&2
        if [[ -z $first ]]; then
            warn "It can't be empty."
            continue
        fi
        read -rsp "Again: " second || die "No input, aborting."
        printf '\n' >&2
        if [[ $first == "$second" ]]; then break; fi
        warn "They don't match."
    done
    printf '%s\n' "$first" | mkpasswd -m yescrypt -s
}

# --- Progress for long steps ---

# Bytes received on every network interface but loopback, so far.
rx_bytes() {
    awk 'NR > 2 {
        name = $0; sub(/:.*/, "", name); gsub(/ /, "", name)
        line = $0; sub(/^[^:]*:/, "", line); split(line, field, " ")
        if (name != "lo") total += field[1]
    } END { print total + 0 }' /proc/net/dev 2>/dev/null || echo 0
}

# Memory still available (MemAvailable), in MiB.
free_mib() { awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null || echo 0; }

# 75 -> "1m15s".
duration() { if (($1 >= 60)); then printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); else printf '%ds' "$1"; fi; }

# with_progress LABEL LOG COMMAND... — runs COMMAND (its output going to
# LOG) under a status line updated every second: time so far, what's been
# downloaded meanwhile, and the CPU time the command has used. There's no
# way to know how long nix will take, but numbers that keep moving show
# it isn't stuck. Returns COMMAND's status; ELAPSED is how long it took.
ELAPSED=0
with_progress() {
    local label=$1 log=$2 pid start rx_start cpu free status=0 tick
    tick=$(getconf CLK_TCK 2>/dev/null) || tick=100
    shift 2
    "$@" >"$log" 2>&1 &
    pid=$!
    start=$SECONDS rx_start=$(rx_bytes)
    while kill -0 "$pid" 2>/dev/null; do
        if [[ -t 1 ]]; then
            # utime + stime, fields 14 and 15 of /proc/PID/stat, in ticks.
            cpu=$(awk -v tick="$tick" '{ print int(($14 + $15) / tick) }' "/proc/$pid/stat" 2>/dev/null) || cpu=0
            free=$(free_mib)
            printf '\r\e[K    %s %s · %d MiB downloaded · %s of CPU · %s MiB RAM free%s' "$label" \
                "$(duration $((SECONDS - start)))" $((($(rx_bytes) - rx_start) / 1048576)) "$(duration "${cpu:-0}")" \
                "$free" "$( ((free < 300)) && printf ' — nearly out of memory!')"
        fi
        sleep 1
    done
    wait "$pid" || status=$?
    ELAPSED=$((SECONDS - start))
    if [[ -t 1 ]]; then printf '\r\e[K'; fi
    return "$status"
}

# Downloads the flake's inputs one by one, with a count, before the
# evaluation: on a fresh ISO that's most of its wait, and inside `nix eval`
# it happens silently. Each lands in the store where the evaluation looks
# first (same locked revision and hash), so nothing is downloaded twice.
# Transitive inputs are left to the evaluation, which fetches only the ones
# it uses. A failure here isn't fatal: the evaluation tries again.
fetch_inputs() {
    local lock=$CONFIG_DIR/flake.lock expr names name i=0 count
    [[ -f $lock ]] || return 0
    expr="let lock = builtins.fromJSON (builtins.readFile $lock); root = lock.nodes.\${lock.root}.inputs; in"
    # Direct inputs only (a list instead of a node name is a `follows`).
    names=$(nix eval --impure --raw --expr "$expr toString (builtins.filter (name: builtins.isString root.\${name}) (builtins.attrNames root))" 2>/dev/null) || return 0
    count=$(wc -w <<<"$names")
    info "Downloading the $count flake inputs (the ones already here take no time):"
    for name in $names; do
        i=$((i + 1))
        # `dir` (a flake in a subfolder) is the flake's business, not the fetcher's.
        if with_progress "[$i/$count] $name" "$WORK/fetch.log" \
            nix eval --impure --raw --expr "$expr (builtins.fetchTree (removeAttrs lock.nodes.\${root.\"$name\"}.locked [ \"dir\" ])).outPath"; then
            info "[$i/$count] $name ($(duration "$ELAPSED"))"
        else
            warn "[$i/$count] $name: couldn't download it now; the evaluation tries again."
        fi
    done
}

# --- Block devices ---

# lsblk rows as fields separated by SEP, in the order of the -o columns.
# lsblk -P hex-escapes anything unsafe in a value (a space becomes \x20),
# so SEP never shows up inside one. (lsblk -r can't be split reliably: an
# empty field there is just two spaces in a row.)
SEP=$'\x1f'
lsblk_rows() {
    local line rest row re='^ *[A-Z0-9_:%-]+="([^"]*)"(.*)$'
    lsblk -Pp "$@" | while IFS= read -r line; do
        row='' rest=$line
        while [[ $rest =~ $re ]]; do
            row+=${BASH_REMATCH[1]}$SEP
            rest=${BASH_REMATCH[2]}
        done
        printf '%s\n' "${row%"$SEP"}"
    done
}

# Undoes lsblk/findmnt's \xNN escapes, for display.
unescape() { printf '%b' "$1"; }

# Mount points (or [SWAP]) of a disk and everything on it, space-separated.
disk_mounts() {
    local mounts
    mounts=$(lsblk -nrpo MOUNTPOINT "$1" 2>/dev/null) || true
    unescape "$(tr -s '\n' ' ' <<<"$mounts" | sed 's/^ *//; s/ *$//')"
}

# "nvme0n1p1 512M vfat · nvme0n1p2 931G crypto_LUKS" for what's on a disk.
disk_contents() {
    local disk=$1 name size fstype label out=''
    while IFS=$SEP read -r -u 3 name size fstype label; do
        if [[ $name == "$disk" && -z $fstype ]]; then continue; fi
        label=$(unescape "$label")
        out+="${out:+ · }${name#/dev/} $size${fstype:+ $fstype}${label:+ \"$label\"}"
    done 3< <(lsblk_rows -n -o NAME,SIZE,FSTYPE,LABEL "$disk")
    printf '%s\n' "${out:-no partitions}"
}

# The most stable path for a whole disk: a /dev/disk/by-id link, preferring
# the model_serial kind over WWN/EUI ones and the shortest name (which skips
# NVMe's "..._1" namespace duplicate). Falls back to by-path, then to the
# kernel name (e.g. an unserialised virtual disk).
disk_id() {
    local disk=$1 link name rank best='' best_rank=99999
    for link in /dev/disk/by-id/*; do
        name=${link##*/}
        if [[ $name =~ -part[0-9]+$ || $(readlink -f "$link") != "$disk" ]]; then continue; fi
        case $name in
            wwn-* | nvme-eui.* | nvme-nvme.*) rank=$((10000 + ${#name})) ;;
            *) rank=${#name} ;;
        esac
        if ((rank < best_rank)); then best=$link best_rank=$rank; fi
    done
    if [[ -z $best ]]; then
        for link in /dev/disk/by-path/*; do
            if [[ ! $link =~ -part[0-9]+$ && $(readlink -f "$link") == "$disk" ]]; then
                best=$link
                break
            fi
        done
    fi
    printf '%s\n' "${best:-$disk}"
}

# "passed", "FAILED", or nothing when SMART can't tell (USB bridges, VMs).
disk_health() {
    local out
    if ((EUID != 0)) || ! command -v smartctl >/dev/null; then return 0; fi
    out=$(smartctl -H "$1" 2>/dev/null) || true
    if grep -qE 'PASSED|Health Status: OK' <<<"$out"; then
        echo passed
    elif grep -q 'FAILED' <<<"$out"; then
        echo FAILED
    fi
}

# --- Setup and preflight ---

DRY_RUN=0 RESUME=0 HOST_ARG='' DISK_ARG='' AGE_KEY_ARG='' SOURCE_ARG=''

usage() {
    cat <<'EOF'
Usage: sudo bash fresh-install.sh [options] [SOURCE]

Installs NixOS from this repo onto a disk of your choice, from the live ISO.
It asks everything up front; nothing is written to any disk until you type
YES.

SOURCE    the repo to install: a directory (or a folder holding it), or a
          git URL to clone. Default: search USB sticks, then other drives.

Options:
  --host NAME       install hosts/NAME instead of asking which machine this is
  --disk DEVICE     install on DEVICE (e.g. /dev/nvme0n1) instead of asking
  --age-key FILE    use this age private key instead of searching for one
  --resume          carry on with an install that stopped after the disk was
                    set up (nixos-install failed or was interrupted), in the
                    same live session: no questions, no wipe
  --dry-run         ask and check everything, evaluate the configuration,
                    then stop before touching any disk. Works without root,
                    but then only already-mounted drives get searched.
  -h, --help        show this help

docs/installing.md covers the whole reinstall, before and after this script.
EOF
}

parse_args() {
    while (($#)); do
        case $1 in
            --dry-run) DRY_RUN=1 ;;
            --resume) RESUME=1 ;;
            --host)
                HOST_ARG=${2-}
                [[ -n $HOST_ARG ]] || die "--host needs a machine name (a folder in hosts/)."
                shift
                ;;
            --disk)
                DISK_ARG=${2-}
                [[ -n $DISK_ARG ]] || die "--disk needs a device."
                shift
                ;;
            --age-key)
                AGE_KEY_ARG=${2-}
                [[ -r $AGE_KEY_ARG ]] || die "--age-key needs a readable file."
                AGE_KEY_ARG=$(realpath "$AGE_KEY_ARG")
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            -*) die "Unknown option $1 (see --help)." ;;
            *)
                [[ -z $SOURCE_ARG ]] || die "Only one SOURCE, please (see --help)."
                SOURCE_ARG=$1
                # Relative to where it was started; it works from / below.
                if [[ -e $SOURCE_ARG ]]; then SOURCE_ARG=$(realpath "$SOURCE_ARG"); fi
                ;;
        esac
        shift
    done
    cd /
}

setup() {
    if ((EUID == 0)); then
        # RAM: the ISO's root filesystem is a tmpfs.
        WORK=/root/fresh-install
        SCAN_ROOT=/run/fresh-install
    elif ((DRY_RUN)); then
        WORK=$(mktemp -d "${TMPDIR:-/tmp}/fresh-install.XXXXXX")
        SCAN_ROOT=''
        warn "Not root: only drives that are already mounted get searched, and SMART isn't checked."
    else
        die "Run it as root: sudo bash fresh-install.sh (or try it out with --dry-run)."
    fi
    # Its answers come from the keyboard; piped in (curl | bash), the
    # prompts would read the script itself.
    if ((!DRY_RUN)) && [[ ! -t 0 ]]; then die "Run it from a terminal: it has questions to ask."; fi
    SRC_COPY=$WORK/repo     # the chosen copy, whole (becomes ~/nixos)
    CONFIG_DIR=$WORK/config # the one that's patched and built, without .git
    mkdir -p "$WORK"
    trap unmount_scans EXIT
    trap 'exit 130' INT TERM
}

# The live ISO keeps everything in RAM — its root filesystem, every
# download, the store — and has no swap. Evaluating the configuration takes
# about 2 GB on top. Short on memory, Linux doesn't kill anything: it keeps
# dropping and re-reading program code from the stick, and the install
# crawls for hours with nothing on screen. Below 8 GB of RAM, compressed
# swap in RAM (zram) gives it room: what fills it is mostly source code,
# which compresses several times over. Live system only; no disk is touched.
check_memory() {
    local total_mib device
    total_mib=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
    info "RAM: $((total_mib / 1024)) GB, $(free_mib) MiB free."
    # (Not in a dry run, which changes nothing, and needs root anyway.)
    if ((total_mib >= 8192 || EUID != 0 || DRY_RUN)); then return 0; fi
    if awk 'NR > 1 { found = 1 } END { exit !found }' /proc/swaps; then return 0; fi
    if modprobe zram 2>/dev/null && device=$(zramctl --find --size "${total_mib}M" --algorithm zstd 2>/dev/null) &&
        mkswap "$device" >/dev/null && swapon --priority 100 "$device"; then
        ok "Added ${total_mib} MiB of compressed swap in RAM ($device), so the install doesn't run out of memory."
    else
        warn "Couldn't add swap, and with $((total_mib / 1024)) GB of RAM the evaluation and install may crawl. If it seems stuck, watch the free RAM on its status line."
    fi
    if ((total_mib < 4096)); then
        warn "Under 4 GB of RAM: installing this configuration from the live ISO may still be very slow."
    fi
}

check_uefi() {
    [[ -d /sys/firmware/efi ]] || die "The ISO was booted in legacy BIOS mode, but this config boots with systemd-boot, which needs UEFI. Boot the stick again through its \"UEFI:\" entry in the firmware's boot menu."
}

online() { curl -sf --max-time 10 -o /dev/null https://cache.nixos.org/nix-cache-info; }

check_network() {
    step "Network"
    while ! online; do
        warn "Can't reach cache.nixos.org, and the install downloads nearly everything from it."
        if command -v nmcli >/dev/null; then
            if confirm "Connect to a Wi-Fi network?" y; then
                connect_wifi
                continue
            fi
        else
            info "Plug in Ethernet, or set up Wi-Fi from another console (wpa_cli, see the NixOS manual)."
        fi
        confirm "Check again?" y || die "Aborted: no network."
    done
    ok "Online."
}

connect_wifi() {
    local ssid
    nmcli radio wifi on 2>/dev/null || true
    nmcli -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null | sed 's/^/    /' || true
    ssid=$(ask "Network name (SSID)")
    [[ -n $ssid ]] || return 0
    # --ask: nmcli prompts for the password itself, if the network has one.
    nmcli --ask device wifi connect "$ssid" || warn "Couldn't connect to $ssid."
}

# --- Finding the repo and the age key ---

CANDIDATES=()  # "dir<SEP>where": copies of this repo found
KEY_FILES=()   # "file<SEP>where": files holding an age private key
SCAN_MOUNTS=() # mount points this script created
MOUNTED_AT=''

# Mounts a filesystem read-only under SCAN_ROOT; sets MOUNTED_AT.
mount_readonly() {
    local dev=$1 fstype=$2 options=ro
    # A read-only ext3/4 mount still replays a dirty journal, which writes.
    if [[ $fstype == ext[34] ]]; then options+=,noload; fi
    MOUNTED_AT=$SCAN_ROOT/${dev##*/}
    mkdir -p "$MOUNTED_AT"
    if mount -o "$options" "$dev" "$MOUNTED_AT" 2>/dev/null || mount_through_disk "$dev" "$options"; then
        SCAN_MOUNTS+=("$MOUNTED_AT")
        return 0
    fi
    rmdir "$MOUNTED_AT" 2>/dev/null || true
    return 1
}

# A partition on the stick the ISO booted from (the config partition next
# to the ISO): the ISO's filesystem holds that stick's whole disk, so the
# kernel won't open any partition of it ("Can't open blockdev"). A loop
# device over the whole disk, at the partition's offset, reads it anyway.
mount_through_disk() {
    local dev=$1 options=$2 name start size disk
    name=${dev##*/}
    start=$(cat "/sys/class/block/$name/start" 2>/dev/null) || return 1
    size=$(cat "/sys/class/block/$name/size" 2>/dev/null) || return 1
    disk=$(basename "$(readlink -f "/sys/class/block/$name/..")")
    [[ -b /dev/$disk && $disk != "$name" ]] || return 1
    # sysfs counts in 512-byte sectors, whatever the disk's own sector size.
    mount -o "$options,loop,offset=$((start * 512)),sizelimit=$((size * 512))" "/dev/$disk" "$MOUNTED_AT" 2>/dev/null
}

unmount_scans() {
    local mountpoint
    for mountpoint in "${SCAN_MOUNTS[@]}"; do
        umount "$mountpoint" 2>/dev/null || umount -l "$mountpoint" 2>/dev/null || true
        rmdir "$mountpoint" 2>/dev/null || true
    done
    SCAN_MOUNTS=()
}

add_candidate() {
    local dir candidate
    dir=$(realpath "$1")
    for candidate in "${CANDIDATES[@]}"; do
        if [[ ${candidate%%"$SEP"*} == "$dir" ]]; then return 0; fi
    done
    CANDIDATES+=("$dir$SEP$2")
}

# located PATH DIR WHERE — how to show PATH: on a scanned filesystem
# (WHERE names it, DIR is its mount point) as "WHERE → /path/on/it",
# otherwise as is.
located() {
    local rel=${1#"$2"}
    if [[ -n $3 ]]; then printf '%s → %s\n' "$3" "${rel:-/}"; else printf '%s\n' "$1"; fi
}

# search_dir DIR [WHERE] — records the repo copies and age keys under DIR.
search_dir() {
    local dir=$1 where=${2-} file repo
    local prune=(\( -name .git -o -name node_modules -o -path '*/nix/store' \) -prune -o)
    while IFS= read -r -d '' file; do
        repo=${file%/flake.nix}
        if [[ -f $repo/variables.nix && -f $repo/modules/default.nix && -d $repo/hosts ]]; then
            add_candidate "$repo" "$(located "$repo" "$dir" "$where")"
        fi
    done < <(find "$dir" -maxdepth 4 "${prune[@]}" -name flake.nix -type f -print0 2>/dev/null)
    while IFS= read -r -d '' file; do
        if grep -q '^AGE-SECRET-KEY-1' "$file" 2>/dev/null; then
            KEY_FILES+=("$file$SEP$(located "$file" "$dir" "$where")")
        fi
    done < <(find "$dir" -maxdepth 5 "${prune[@]}" -type f -size -32k \( -iname '*key*' -o -iname '*.age' -o -iname '*.txt' \) -print0 2>/dev/null)
}

# scan_devices usb|other — searches every filesystem on USB/removable
# drives, or on all the others.
scan_devices() {
    local want=$1 dev fstype tran hotplug rm label mountpoint removable where disk
    while IFS=$SEP read -r -u 3 dev fstype tran hotplug rm label mountpoint; do
        case $fstype in
            '' | swap | crypto_LUKS | LVM2_member | linux_raid_member | zfs_member | iso9660 | squashfs | BitLocker) continue ;;
        esac
        case ${dev##*/} in zram* | loop* | ram* | sr*) continue ;; esac
        # Only whole disks report their transport reliably; a partition
        # (or a LUKS/LVM volume on one) takes its disk's.
        disk=$(lsblk -nsrpo NAME,TYPE "$dev" 2>/dev/null | awk '$2 == "disk" { print $1; exit }') || disk=''
        if [[ -n $disk && $disk != "$dev" ]]; then
            read -r hotplug rm tran < <(lsblk -dnro HOTPLUG,RM,TRAN "$disk" 2>/dev/null) || true
        fi
        removable=0
        if [[ $tran == usb || $hotplug == 1 || $rm == 1 ]]; then removable=1; fi
        if [[ $want == usb && $removable == 0 ]] || [[ $want == other && $removable == 1 ]]; then continue; fi
        label=$(unescape "$label") mountpoint=$(unescape "$mountpoint")
        where="$dev${label:+ \"$label\"}"
        if [[ -n $mountpoint ]]; then
            # Already mounted. On internal drives, only where people mount
            # things by hand, not the running system's own filesystems.
            if [[ $removable == 0 && ! $mountpoint =~ ^(/mnt|/media|/run/media)(/|$) ]]; then continue; fi
            info "Searching $where (mounted at $mountpoint)"
            search_dir "$mountpoint" "$where"
        elif ((EUID == 0)); then
            if mount_readonly "$dev" "$fstype"; then
                info "Searching $where ($fstype)"
                search_dir "$MOUNTED_AT" "$where"
            else
                info "Skipped $where: couldn't mount its $fstype filesystem."
            fi
        fi
    done 3< <(lsblk_rows -n -o NAME,FSTYPE,TRAN,HOTPLUG,RM,LABEL,MOUNTPOINT)
}

clone_repo() {
    local url=$1 dest=$WORK/clone
    rm -rf "$dest"
    info "Cloning $url"
    if command -v git >/dev/null; then
        git clone --quiet "$url" "$dest" || die "Couldn't clone $url."
    else
        nix run nixpkgs#git -- clone --quiet "$url" "$dest" || die "Couldn't clone $url."
    fi
    search_dir "$dest" "$url"
}

# Unix time of a copy's last commit, or else of its newest .nix file.
repo_timestamp() {
    local dir=$1 time=''
    if [[ -d $dir/.git ]] && command -v git >/dev/null; then
        time=$(git -c safe.directory='*' -C "$dir" log -1 --format=%ct 2>/dev/null) || time=''
    fi
    if [[ -z $time ]]; then
        time=$(find "$dir" -name .git -prune -o -type f -name '*.nix' -printf '%T@\n' 2>/dev/null | sort -n | tail -n 1) || true
        time=${time%.*}
    fi
    printf '%s\n' "${time:-0}"
}

# One line about a copy: its machines, and its last commit or change.
describe_repo() {
    local dir=$1 machines='' last='' changes
    machines=$(list_hosts "$dir" | paste -sd, - | sed 's/,/, /g')
    if [[ -d $dir/.git ]] && command -v git >/dev/null; then
        last=$(git -c safe.directory='*' -C "$dir" log -1 --format='commit %h (%cr): %s' 2>/dev/null) || last=''
        changes=$(git -c safe.directory='*' -C "$dir" status --porcelain --untracked-files=no 2>/dev/null) || changes=''
        if [[ -n $last && -n $changes ]]; then last+=', plus uncommitted changes'; fi
    fi
    if [[ -z $last ]]; then
        last="no git history, last changed $(date -d "@$(repo_timestamp "$dir")" '+%Y-%m-%d %H:%M')"
    fi
    printf 'machines: %s; %s\n' "${machines:-none}" "$last"
}

find_repo() {
    step "Looking for the config"
    local i dir time best=1 best_time=-1 choice=1
    if [[ -n $SOURCE_ARG ]]; then
        if [[ $SOURCE_ARG =~ ^(https?|ssh|git):// || $SOURCE_ARG =~ ^[^/]+@[^/]+: ]]; then
            clone_repo "$SOURCE_ARG"
        else
            [[ -d $SOURCE_ARG ]] || die "$SOURCE_ARG isn't a directory."
            search_dir "$SOURCE_ARG"
        fi
    else
        scan_devices usb
        if ((${#CANDIDATES[@]} == 0)); then
            info "Nothing on USB sticks; trying the other drives."
            scan_devices other
        fi
    fi
    if ((${#CANDIDATES[@]} == 0)); then
        die "No copy of this repo found (flake.nix, variables.nix, modules/ and hosts/, at most 4 folders deep). Put it on a USB stick, or give its path or git URL: sudo bash fresh-install.sh <path|url>"
    fi

    if ((${#CANDIDATES[@]} > 1)); then info "Found ${#CANDIDATES[@]} copies:"; fi
    for i in "${!CANDIDATES[@]}"; do
        dir=${CANDIDATES[i]%%"$SEP"*}
        printf '  %2d) %s\n      %s%s%s\n' $((i + 1)) "${CANDIDATES[i]#*"$SEP"}" "$DIM" "$(describe_repo "$dir")" "$RESET"
        time=$(repo_timestamp "$dir")
        if ((time > best_time)); then best=$((i + 1)) best_time=$time; fi
    done
    if ((${#CANDIDATES[@]} > 1)); then choice=$(choose "${#CANDIDATES[@]}" "$best"); fi
    SOURCE_DIR=${CANDIDATES[choice - 1]%%"$SEP"*}
    SOURCE_DESC=${CANDIDATES[choice - 1]#*"$SEP"}

    # The disk the copy is on (through any LUKS/LVM layers), to point it
    # out in the disk list. findmnt shows a btrfs subvolume as dev[/subvol].
    local source_dev
    source_dev=$(findmnt -nro SOURCE -T "$SOURCE_DIR" 2>/dev/null) || source_dev=''
    source_dev=${source_dev%%\[*}
    SOURCE_DISK=''
    if [[ $source_dev == /dev/* ]]; then
        SOURCE_DISK=$(lsblk -nsrpo NAME,TYPE "$source_dev" 2>/dev/null | awk '$2 == "disk" { print $1; exit }') || SOURCE_DISK=''
    fi
}

# Files copied off a FAT/exFAT stick all come out executable, which would
# show up in ~/nixos as a mode change on every file. Restores the modes git
# recorded, or plain 644 (755 for scripts) without git.
fix_modes() {
    local dir=$1 entry
    find "$dir" -name .git -prune -o -type d -exec chmod 755 {} + -o -type f -exec chmod 644 {} +
    if [[ -d $dir/.git ]] && command -v git >/dev/null; then
        while IFS= read -r -d '' entry; do
            if [[ $entry == 100755\ * ]]; then chmod 755 "$dir/${entry#*$'\t'}"; fi
        done < <(git -c safe.directory='*' -C "$dir" ls-files -s -z 2>/dev/null)
    else
        find "$dir" -name '*.sh' -type f -exec chmod 755 {} +
    fi
}

# An age private key kept in the repo folder on the stick (find_age_key
# reads it from there) must not come along: the build copy is copied into
# the world-readable Nix store when it's evaluated, and the whole copy
# becomes ~/nixos, one `git add` away from a public repo.
strip_age_keys() {
    local dir=$1 file
    while IFS= read -r -d '' file; do
        if grep -q '^AGE-SECRET-KEY-1' "$file" 2>/dev/null; then
            rm -f "$file"
            info "Left the age key ${file#"$dir"/} out of the copy (it's installed separately)."
        fi
    done < <(find "$dir" -name .git -prune -o -type f -size -32k -print0 2>/dev/null)
}

copy_source() {
    rm -rf "$SRC_COPY" "$CONFIG_DIR"
    mkdir -p "$SRC_COPY"
    cp -a "$SOURCE_DIR"/. "$SRC_COPY"/
    rm -f "$SRC_COPY"/result "$SRC_COPY"/result-*
    strip_age_keys "$SRC_COPY"
    fix_modes "$SRC_COPY"
    # Built without .git: a git flake only sees tracked files, and this has
    # to build whatever is on the stick.
    cp -a "$SRC_COPY" "$CONFIG_DIR"
    rm -rf "$CONFIG_DIR/.git"
    if [[ ! -f $CONFIG_DIR/flake.lock ]]; then
        warn "This copy has no flake.lock: every input gets locked to its latest version."
    fi
    USERNAME=$(nix eval --raw --file "$CONFIG_DIR/variables.nix" username) || die "Couldn't read username from variables.nix."
    ok "Using $SOURCE_DESC (user $USERNAME), copied to $WORK."
}

# --- The machine ---

HOST='' # the machine being installed: its folder in hosts/

# host_file — the machine's own variables.nix.
host_file() { printf '%s\n' "$CONFIG_DIR/hosts/$HOST/variables.nix"; }

# host_eval EXPR — prints EXPR (a string), with `v` bound to the machine's
# variables: variables.nix overlaid with its hosts/<name>/variables.nix,
# as flake.nix merges them.
host_eval() {
    nix eval --impure --raw --expr "let v = import $CONFIG_DIR/variables.nix // import $(host_file); in $1" 2>/dev/null
}

# set_host_line NAME VALUE — rewrites the machine's one-line `NAME = ...;`
# to `NAME = VALUE;` (VALUE in Nix syntax: true, "amd", [ "amd" ], ...).
set_host_line() {
    local name=$1 value=$2 file lines
    file=$(host_file)
    lines=$(grep -cE "^[[:space:]]*$name = .*;[[:space:]]*$" "$file") || true
    [[ $lines == 1 ]] || die "hosts/$HOST/variables.nix has ${lines:-0} one-line '$name = ...;' entries instead of one; set it there by hand."
    value=${value//\\/\\\\}
    value=${value//&/\\&}
    sed -i -E "s|^([[:space:]]*$name = ).*;([[:space:]]*)$|\1$value;\2|" "$file"
}

# What this machine actually has, read from sysfs.
DETECTED_LAPTOP=0 DETECTED_CPU='' DETECTED_GPUS=''
declare -gA DETECTED_BUS_IDS=() # GPU vendor -> "PCI:bus:device:function"

detect_hardware() {
    local supply dev addr vendor bus_id
    local -A found=()
    DETECTED_LAPTOP=0 DETECTED_CPU='' DETECTED_GPUS=''
    DETECTED_BUS_IDS=()
    # A laptop has a system battery (a mouse's or headset's is "Device"
    # scope), or says so in its DMI chassis type.
    for supply in /sys/class/power_supply/*; do
        if [[ $(cat "$supply/type" 2>/dev/null) == Battery && $(cat "$supply/scope" 2>/dev/null) != Device ]]; then
            DETECTED_LAPTOP=1
        fi
    done
    case $(cat /sys/class/dmi/id/chassis_type 2>/dev/null) in
        8 | 9 | 10 | 11 | 14 | 30 | 31 | 32) DETECTED_LAPTOP=1 ;; # portable, laptop, notebook, ..., convertible
    esac
    case $(grep -m 1 '^vendor_id' /proc/cpuinfo 2>/dev/null) in
        *GenuineIntel*) DETECTED_CPU=intel ;;
        *AuthenticAMD*) DETECTED_CPU=amd ;;
    esac
    # Display controllers (PCI class 0x03xx), by vendor.
    for dev in /sys/bus/pci/devices/*; do
        [[ $(cat "$dev/class" 2>/dev/null) == 0x03* ]] || continue
        case $(cat "$dev/vendor" 2>/dev/null) in
            0x1002) vendor=amd ;;
            0x8086) vendor=intel ;;
            0x10de) vendor=nvidia ;;
            *) continue ;;
        esac
        found[$vendor]=1
        # sysfs names it domain:bus:device.function, in hex; NixOS wants
        # PCI:bus:device:function in decimal (bus@domain outside domain 0).
        addr=${dev##*/}
        if [[ ${addr:0:4} == 0000 ]]; then
            bus_id=$(printf 'PCI:%d:%d:%d' "0x${addr:5:2}" "0x${addr:8:2}" "0x${addr:11:1}")
        else
            bus_id=$(printf 'PCI:%d@%d:%d:%d' "0x${addr:5:2}" "0x${addr:0:4}" "0x${addr:8:2}" "0x${addr:11:1}")
        fi
        # Two GPUs from one vendor: the one the firmware booted on.
        if [[ -z ${DETECTED_BUS_IDS[$vendor]-} || $(cat "$dev/boot_vga" 2>/dev/null) == 1 ]]; then
            DETECTED_BUS_IDS[$vendor]=$bus_id
        fi
    done
    for vendor in amd intel nvidia; do
        if [[ -n ${found[$vendor]-} ]]; then DETECTED_GPUS+="${DETECTED_GPUS:+ }$vendor"; fi
    done
}

# One line about a machine in hosts/: laptop or desktop, CPU, GPUs, keyboard.
describe_host() {
    local saved=$HOST description
    HOST=$1
    description=$(host_eval '(if v.isLaptop then "laptop" else "desktop") + ", " + v.cpu + " CPU, GPUs: " + toString v.gpus + ", keyboard: " + v.keyboardLayout + (if v.keyboardVariant != "" then " " + v.keyboardVariant else "") + (if v.keyboardModel != "" then " (" + v.keyboardModel + ")" else "")') || description='(its variables.nix does not evaluate)'
    HOST=$saved
    printf '%s\n' "$description"
}

# How closely a machine in hosts/ matches the detected hardware (0-4).
host_score() {
    local saved=$HOST facts score=0
    HOST=$1
    facts=$(host_eval '(if v.isLaptop then "1" else "0") + " " + v.cpu + " " + toString (builtins.sort builtins.lessThan v.gpus)') || facts=''
    HOST=$saved
    if [[ ${facts%% *} == "$DETECTED_LAPTOP" ]]; then score=$((score + 1)); fi
    facts=${facts#* }
    if [[ ${facts%% *} == "$DETECTED_CPU" ]]; then score=$((score + 1)); fi
    if [[ ${facts#* } == "$DETECTED_GPUS" ]]; then score=$((score + 2)); fi
    printf '%s\n' "$score"
}

# Sets up hosts/NAME as a copy of hosts/TEMPLATE's variables. Its
# hardware-configuration.nix is generated later (check_hardware_config).
new_host() {
    local name=$1 template=$2
    mkdir -p "$CONFIG_DIR/hosts/$name"
    # The template's opening "# name: description" paragraph, if it has
    # one, is about the template: replaced with one about the copy.
    awk -v name="$name" -v template="$template" '
        NR == 1 && index($0, "# " template ": ") == 1 {
            print "# " name ": set up by fresh-install.sh, from " template "'"'"'s settings."
            skip = 1; next
        }
        skip && /^# / { next }
        { skip = 0; print }
    ' "$CONFIG_DIR/hosts/$template/variables.nix" >"$CONFIG_DIR/hosts/$name/variables.nix"
    ok "hosts/$name: new, starting from $template's settings."
}

# list_hosts [REPO] — the machines in hosts/, sorted (a glob would put
# hyena-lt-home/ before hyena/, since - sorts before /).
list_hosts() {
    local file
    for file in "${1:-$CONFIG_DIR}"/hosts/*/variables.nix; do
        file=${file%/variables.nix}
        printf '%s\n' "${file##*/}"
    done | LC_ALL=C sort
}

choose_host() {
    step "Which machine this is"
    local hosts=("$CONFIG_DIR"/hosts/*/variables.nix)
    ((${#hosts[@]})) || die "This copy has no machines in hosts/."
    detect_hardware
    info "This one: $( ((DETECTED_LAPTOP)) && echo laptop || echo desktop), ${DETECTED_CPU:-unknown} CPU, GPUs: ${DETECTED_GPUS:-none found}"

    if [[ -n $HOST_ARG ]]; then
        [[ -f $CONFIG_DIR/hosts/$HOST_ARG/variables.nix ]] || die "--host $HOST_ARG: there's no hosts/$HOST_ARG/variables.nix."
        HOST=$HOST_ARG
    else
        pick_host
    fi
    # Everything after this reads the machine's variables, so they have to
    # evaluate.
    host_eval 'toString v.isLaptop' >/dev/null || die "hosts/$HOST/variables.nix doesn't evaluate; \`nix eval --file $(host_file)\` shows why."
    ok "$HOST: $(describe_host "$HOST")"
}

# The machine menu, or a new machine.
pick_host() {
    local -a hosts=()
    local name i n score best=1 best_score=-1 choice template
    mapfile -t hosts < <(list_hosts)

    for i in "${!hosts[@]}"; do
        score=$(host_score "${hosts[i]}")
        if ((score > best_score)); then best=$((i + 1)) best_score=$score; fi
    done
    for i in "${!hosts[@]}"; do
        printf '  %2d) %-18s %s%s\n' $((i + 1)) "${hosts[i]}" "$(describe_host "${hosts[i]}")" \
            "$([[ $((i + 1)) == "$best" && $best_score == 4 ]] && echo "  ← matches")"
    done
    n=$((${#hosts[@]} + 1))
    printf '  %2d) %s\n' "$n" "a new machine, starting from a copy of one of these"
    choice=$(choose "$n" "$best")

    if ((choice < n)); then
        HOST=${hosts[choice - 1]}
        return 0
    fi
    while true; do
        name=$(ask "Name for it (its hostname too: lowercase letters, digits, dashes)")
        if [[ ! $name =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
            warn "Not a valid hostname."
        elif [[ -e $CONFIG_DIR/hosts/$name ]]; then
            warn "hosts/$name already exists."
        else
            break
        fi
    done
    info "Start from which machine's settings (keyboard, monitors, modules left out)?"
    for i in "${!hosts[@]}"; do printf '  %2d) %s\n' $((i + 1)) "${hosts[i]}"; done
    choice=$(choose "${#hosts[@]}" "$best")
    template=${hosts[choice - 1]}
    new_host "$name" "$template"
    HOST=$name
}

# Asks whether it's a laptop, and brings the machine's cpu, gpus and NVIDIA
# bus IDs in line with the hardware that's actually here.
check_machine() {
    local laptop answer=n cpu gpus nix_list ids vendor missing=''
    if ((DETECTED_LAPTOP)); then answer=y; fi
    if confirm "Is this machine a laptop?" "$answer"; then laptop=true; else laptop=false; fi
    if [[ $(host_eval 'if v.isLaptop then "true" else "false"') != "$laptop" ]]; then
        set_host_line isLaptop "$laptop"
        ok "hosts/$HOST: isLaptop = $laptop."
    fi

    cpu=$(host_eval v.cpu) || cpu=''
    if [[ -n $DETECTED_CPU && $cpu != "$DETECTED_CPU" ]]; then
        warn "hosts/$HOST says cpu = \"$cpu\", but this machine's CPU is $DETECTED_CPU."
        if confirm "Change it to \"$DETECTED_CPU\"?" y; then set_host_line cpu "\"$DETECTED_CPU\""; fi
    fi

    gpus=$(host_eval 'toString (builtins.sort builtins.lessThan v.gpus)') || gpus=''
    if [[ -n $DETECTED_GPUS && $gpus != "$DETECTED_GPUS" ]]; then
        warn "hosts/$HOST says gpus = [ $gpus ], but this machine has: $DETECTED_GPUS."
        if confirm "Change it to what's here?" y; then
            nix_list=''
            for vendor in $DETECTED_GPUS; do nix_list+=" \"$vendor\""; done
            set_host_line gpus "[$nix_list ]"
            gpus=$DETECTED_GPUS
        fi
    fi

    # NVIDIA next to integrated graphics: PRIME needs both PCI addresses.
    if [[ " $gpus " == *" nvidia "* && ( " $gpus " == *" amd "* || " $gpus " == *" intel "* ) ]]; then
        ids=''
        for vendor in $gpus; do
            if [[ -n ${DETECTED_BUS_IDS[$vendor]-} ]]; then
                ids+=" $vendor = \"${DETECTED_BUS_IDS[$vendor]}\";"
            else
                missing+=" $vendor"
            fi
        done
        if [[ -z $missing ]]; then
            set_host_line gpuBusIds "{$ids }"
            ok "hosts/$HOST: gpuBusIds = {$ids }, for NVIDIA PRIME."
        else
            warn "No PCI address found for:$missing. Set gpuBusIds in hosts/$HOST/variables.nix by hand (lspci -D)."
        fi
    fi
}

# Passwords typed from here on have to be the ones the installed system
# expects, so the ISO's keyboard switches to the machine's keymap. US-based
# ones need nothing: the ISO's default US types the same characters (and
# it's what reads the LUKS passphrase at boot too — see system/base.nix).
use_host_keymap() {
    local keymap layout
    keymap=$(host_eval v.consoleKeyMap) || keymap=''
    if [[ -z $keymap || $keymap == us || $keymap == us-* ]]; then return 0; fi
    layout=$(host_eval 'v.keyboardLayout + (if v.keyboardVariant != "" then " " + v.keyboardVariant else "")') || layout=$keymap
    if ((DRY_RUN)); then
        info "$HOST uses a $keymap keyboard; the real run switches the ISO to it before the password questions."
    elif [[ $(tty 2>/dev/null) == /dev/tty[0-9]* ]] && command -v loadkeys >/dev/null && loadkeys "$keymap" >/dev/null 2>&1; then
        ok "Keyboard switched to $keymap, $HOST's layout: passwords typed here are the ones it'll expect."
    else
        warn "$HOST uses a $layout keyboard ($keymap). Switch this session to that layout before the password questions, or the passwords typed here won't match once installed."
    fi
}

AGE_KEY=''      # the verified key, in RAM until it's installed
AGE_KEY_FROM='' # where it was found
AGE_KEYGEN=''
RECIPIENTS=''

# age-keygen isn't on the ISO: built from the config's own pinned nixpkgs.
get_age_keygen() {
    local out
    if [[ -n $AGE_KEYGEN ]]; then return 0; fi
    if command -v age-keygen >/dev/null; then
        AGE_KEYGEN=age-keygen
        return 0
    fi
    info "Fetching age, to check the keys (this downloads nixpkgs, which the install needs anyway):"
    with_progress "fetching age" "$WORK/age.log" \
        nix build --no-link --print-out-paths --inputs-from "$CONFIG_DIR" nixpkgs#age || return 1
    out=$(grep -m 1 '^/nix/store/' "$WORK/age.log") || return 1
    AGE_KEYGEN=$out/bin/age-keygen
}

# try_age_key FILE WHERE — keeps the key in FILE that secrets.yaml is
# encrypted for, if there is one.
try_age_key() {
    local file=$1 where=$2 line public
    [[ -r $file ]] || return 1
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        [[ $line == AGE-SECRET-KEY-1* ]] || continue
        public=$(printf '%s\n' "$line" | "$AGE_KEYGEN" -y 2>/dev/null) || continue
        if grep -qxF "$public" <<<"$RECIPIENTS"; then
            (umask 077 && printf '# public key: %s\n%s\n' "$public" "$line" >"$WORK/age-key.txt")
            AGE_KEY=$WORK/age-key.txt AGE_KEY_FROM=$where
            ok "Found it: $where"
            return 0
        fi
    done <"$file"
    return 1
}

find_age_key() {
    step "Age key"
    local entry path
    RECIPIENTS=$(grep -oE 'age1[0-9a-z]{58}' "$CONFIG_DIR/secrets/secrets.yaml" 2>/dev/null | sort -u) || true
    if [[ -z $RECIPIENTS ]]; then
        info "No age-encrypted secrets/secrets.yaml, so no key to look for."
        return 0
    fi
    info "secrets/secrets.yaml is encrypted for ${RECIPIENTS//$'\n'/, }"
    if [[ -n $AGE_KEY_ARG ]]; then KEY_FILES=("$AGE_KEY_ARG$SEP$AGE_KEY_ARG" "${KEY_FILES[@]}"); fi
    if ((${#KEY_FILES[@]} == 0)); then
        info "No age key on the drives searched."
    elif ! get_age_keygen; then
        warn "Couldn't get age-keygen to check the keys found."
    else
        for entry in "${KEY_FILES[@]}"; do
            if try_age_key "${entry%%"$SEP"*}" "${entry#*"$SEP"}"; then return 0; fi
        done
        warn "None of the age keys found is the one for that. Checked:"
        for entry in "${KEY_FILES[@]}"; do info "  ${entry#*"$SEP"}"; done
    fi
    while true; do
        path=$(ask "Path to the key file, or Enter to install without secrets")
        [[ -n $path ]] || break
        if get_age_keygen && try_age_key "$path" "$path"; then return 0; fi
        warn "That's not it."
    done
    warn "Installing without $SECRETS_MODULE and the modules that need it. docs/installing.md has how to add them back."
}

# --- The disk ---

DISK='' DISK_ID='' DISK_DESC='' DISK_HEALTH=''
USER_HASH='' ROOT_HASH=''

choose_disk() {
    step "Disk to install on"
    local configured configured_disk='' disk type size model tran hotplug mounts mark n=0 default='' fixed=0 fixed_n='' choice want i bytes
    local -a pick=() pick_desc=()
    configured=$(host_eval v.disk) || configured=''
    if [[ -n $configured && -e $configured ]]; then configured_disk=$(readlink -f "$configured"); fi

    while IFS=$SEP read -r -u 3 disk type size model tran hotplug; do
        [[ $type == disk ]] || continue
        case ${disk##*/} in zram* | loop* | ram* | sr* | fd* | nbd*) continue ;; esac
        model=$(unescape "$model")
        mounts=$(disk_mounts "$disk")
        if [[ -n $mounts ]]; then
            printf '   %s-  %-14s %7s  %-24.24s %-5s in use: %s%s\n' "$DIM" "$disk" "$size" "$model" "$tran" "$mounts" "$RESET"
            continue
        fi
        n=$((n + 1))
        pick[n]=$disk pick_desc[n]="$size ${model:-disk}${tran:+, $tran}"
        mark=''
        if [[ $disk == "$configured_disk" ]]; then
            mark+="  ← $HOST's disk"
            default=$n
        fi
        if [[ $disk == "$SOURCE_DISK" ]]; then mark+="  (holds the config copy you picked)"; fi
        printf '  %2d) %-14s %7s  %-24.24s %-5s%s\n' "$n" "$disk" "$size" "$model" "$tran" "$mark"
        printf '      %s%s%s\n' "$DIM" "$(disk_contents "$disk")" "$RESET"
        if [[ $tran != usb && $hotplug != 1 ]]; then fixed=$((fixed + 1)) fixed_n=$n; fi
    done 3< <(lsblk_rows -dn -o NAME,TYPE,SIZE,MODEL,TRAN,HOTPLUG)

    if ((n == 0)); then
        if ((DRY_RUN)); then
            warn "No disk to install on (they're all in use), so the disk step is skipped in this dry run."
            return 0
        fi
        die "No disk to install on: every disk is in use. Unmount what's mounted from the one you want, then run this again."
    fi
    # The machine's disk isn't here: default to the only internal one, if so.
    if [[ -z $default && $fixed == 1 ]]; then default=$fixed_n; fi

    while true; do
        if [[ -n $DISK_ARG ]]; then
            want=$(readlink -f "$DISK_ARG" 2>/dev/null || true)
            if [[ ! -b $want ]]; then want=$(readlink -f "/dev/$DISK_ARG" 2>/dev/null || true); fi
            choice=''
            for i in "${!pick[@]}"; do
                if [[ ${pick[i]} == "$want" ]]; then choice=$i; fi
            done
            [[ -n $choice ]] || die "--disk $DISK_ARG isn't one of the disks above that can be installed on."
            DISK_ARG=''
        else
            choice=$(choose "$n" "$default")
        fi
        DISK=${pick[choice]} DISK_DESC=${pick_desc[choice]}

        bytes=$(lsblk -dnbo SIZE "$DISK")
        if ((bytes < 64 * 1024 ** 3)); then
            warn "$DISK is only ${DISK_DESC%% *}: the system alone takes tens of GB (Steam, the VM, ...)."
            confirm "Use it anyway?" n || continue
        fi
        DISK_HEALTH=$(disk_health "$DISK")
        if [[ $DISK_HEALTH == FAILED ]]; then
            warn "SMART says $DISK is failing."
            confirm "Install on it anyway?" n || continue
        fi
        break
    done

    DISK_ID=$(disk_id "$DISK")
    if [[ $DISK_ID == /dev/disk/by-path/* || $DISK_ID == "$DISK" ]]; then
        warn "$DISK has no /dev/disk/by-id link; using $DISK_ID, which can change if disks are added or moved."
    fi
    if [[ $DISK_ID == "$configured" ]]; then
        ok "$DISK_ID, already $HOST's disk."
    else
        set_host_line disk "\"$DISK_ID\""
        ok "hosts/$HOST: disk = \"$DISK_ID\" (was ${configured:-unset})."
    fi
    if [[ $DISK == "$SOURCE_DISK" ]]; then
        info "It holds the config you picked, but that's already copied to RAM."
    fi
}

# --- Hardware ---

HW_STATUS='not checked'

check_hardware_config() {
    step "Hardware"
    local current=$CONFIG_DIR/hosts/$HOST/hardware-configuration.nix detected=$WORK/hardware-configuration.nix raw
    local shown=hosts/$HOST/hardware-configuration.nix
    if ! command -v nixos-generate-config >/dev/null || ! {
        # --no-filesystems: disko.nix supplies those. An empty --root keeps
        # it from inspecting mounts at all (which it does even then, and
        # which can fail, e.g. on btrfs without root).
        mkdir -p "$WORK/empty-root"
        raw=$(nixos-generate-config --no-filesystems --show-hardware-config --root "$WORK/empty-root" 2>/dev/null)
    }; then
        [[ -f $current ]] || die "Couldn't detect the hardware (nixos-generate-config), and $shown doesn't exist yet: create it by hand."
        warn "Couldn't detect the hardware (nixos-generate-config); keeping $shown."
        return 0
    fi
    {
        # The header below instead of the generator's, and none of its
        # comments or networking lines (base.nix sets up NetworkManager).
        printf '%s\n' "$HW_HEADER"
        printf '%s\n' "$raw" | sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*networking\.\(useDHCP\|interfaces\.\)/d' | cat -s
    } >"$detected"

    # A new machine, or one only ever set up with a placeholder (the
    # laptops, before their first install): nothing to compare against.
    if [[ ! -f $current ]] || grep -q '^# Placeholder' "$current"; then
        cp "$detected" "$current"
        HW_STATUS='generated for this machine'
        ok "$shown: generated for this machine."
        return 0
    fi
    if [[ $(nix_code "$current") == "$(nix_code "$detected")" ]]; then
        HW_STATUS='matches this machine'
        ok "$shown matches this machine."
        return 0
    fi
    info "This machine differs from $shown:"
    diff -u --label committed --label detected "$current" "$detected" | sed 's/^/      /' || true
    if confirm "Use the detected one?" y; then
        cp "$detected" "$current"
        HW_STATUS='regenerated for this machine'
    else
        HW_STATUS='kept the committed one (differs from this machine)'
    fi
}

# The header of a generated hardware-configuration.nix.
# shellcheck disable=SC2016 # the backticks are literal: it's a comment
HW_HEADER='# Generated by `nixos-generate-config` for this machine: initrd kernel
# modules and CPU microcode. Not portable — fresh-install.sh regenerates it
# on the machine it installs.
#
# The disk layout (fileSystems, swapDevices, boot.initrd.luks.devices) is
# deliberately not here: modules/system/disko.nix supplies it. When
# regenerating by hand, drop those parts from the generated file.'

# The code of a Nix file without comments, blank lines or indentation, for
# comparing.
nix_code() { sed -e 's/#.*$//' -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' "$1" | grep -v '^$' || true; }

NOTES=()

# Things about this machine worth knowing before installing; they don't
# stop anything.
hardware_notes() {
    local connector name output outputs
    local -a connected=() missing=()
    for connector in /sys/class/drm/card*-*; do
        if [[ -r $connector/status && $(<"$connector/status") == connected ]]; then
            name=${connector##*/}
            connected+=("${name#card*-}")
        fi
    done
    ((${#connected[@]})) || return 0
    outputs=$(host_eval 'toString (map (m: m.output) v.monitors)') || return 0
    for output in $outputs; do
        if [[ " ${connected[*]} " != *" $output "* ]]; then missing+=("$output"); fi
    done
    if ((${#missing[@]})); then
        NOTES+=("hosts/$HOST/variables.nix expects monitor output(s) ${missing[*]}, but what's connected is ${connected[*]}. Hyprland lays out unknown outputs automatically; fix the names in its monitors after the first boot.")
    fi
}

# --- Modules ---

MOD_KEYS=() # every module, in file order: "gaming/vr.nix", "home/apps/zen.nix", ...
declare -gA MOD_FILE=() MOD_GROUP=() MOD_REPO=() MOD_ON=() MOD_DESC=() MOD_LOCKED=()
PICK_KEYS=() # picker number -> module

short() { printf '%s\n' "${1%.nix}"; }

is_required() {
    local module
    for module in "${REQUIRED_MODULES[@]}"; do
        if [[ $module == "$1" ]]; then return 0; fi
    done
    return 1
}

# parse_imports FILE KEY_PREFIX GROUP — reads the modules in an imports
# list (a commented-out line isn't one). "# --- Name ---" lines start a new
# group.
parse_imports() {
    local file=$1 prefix=$2 group=$3 line key in_imports=0
    local re_group='^[[:space:]]*#[[:space:]]*---[[:space:]]*(.*[^[:space:]])[[:space:]]*---'
    local re_import='^[[:space:]]*\./([^[:space:]#]+\.nix)'
    [[ -f $file ]] || return 0
    while IFS= read -r line; do
        if ((!in_imports)); then
            if [[ $line =~ imports[[:space:]]*=[[:space:]]*\[ ]]; then in_imports=1; fi
            continue
        fi
        if [[ $line =~ ^[[:space:]]*\]\; ]]; then break; fi
        if [[ $line =~ $re_group ]]; then
            group=${BASH_REMATCH[1]}
            continue
        fi
        [[ $line =~ $re_import ]] || continue
        key=$prefix${BASH_REMATCH[1]}
        MOD_KEYS+=("$key")
        MOD_FILE[$key]=$file MOD_GROUP[$key]=$group
    done <"$file"
}

# One-line descriptions, straight from docs/modules.md.
load_descriptions() {
    local doc=$CONFIG_DIR/docs/modules.md line prefix='' text
    # shellcheck disable=SC2016 # backticks are literal: markdown code spans
    local re_section='^## `([^`]*)`' re_item='^- \*\*`([^`]+)`\*\* — (.*)$'
    [[ -f $doc ]] || return 0
    while IFS= read -r line; do
        if [[ $line =~ $re_section ]]; then
            prefix=${BASH_REMATCH[1]}
            continue
        fi
        if [[ $line == '## '* ]]; then
            prefix='-' # "## Top level": flake.nix and friends, not modules
            continue
        fi
        [[ $line =~ $re_item ]] || continue
        text=${BASH_REMATCH[2]//\`/}
        text=${text//\*\*/}
        MOD_DESC[$prefix${BASH_REMATCH[1]}]=$(sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g' <<<"$text")
    done <"$doc"
}

load_modules() {
    local module disabled
    parse_imports "$CONFIG_DIR/modules/default.nix" "" "System"
    parse_imports "$CONFIG_DIR/modules/home/default.nix" "home/" "Home (home-manager)"
    load_descriptions
    ((${#MOD_KEYS[@]})) || die "Found no imports in modules/default.nix."
    # Where the machine is now: everything but its disabledModules.
    disabled=$'\n'$(host_eval 'builtins.concatStringsSep "\n" v.disabledModules')$'\n' ||
        die "Couldn't read disabledModules from hosts/$HOST/variables.nix."
    for module in "${MOD_KEYS[@]}"; do
        if [[ $disabled == *$'\n'"$module"$'\n'* ]]; then MOD_REPO[$module]=0; else MOD_REPO[$module]=1; fi
    done
}

# needs_of MODULE — the module and everything it needs, transitively.
needs_of() {
    local -A seen=()
    local -a todo=("$1")
    local module dep
    while ((${#todo[@]})); do
        module=${todo[-1]}
        unset 'todo[-1]'
        if [[ -n ${seen[$module]-} ]]; then continue; fi
        seen[$module]=1
        printf '%s\n' "$module"
        for dep in ${MODULE_NEEDS[$module]-}; do
            if [[ -n ${MOD_FILE[$dep]-} ]]; then todo+=("$dep"); fi
        done
    done
}

# dependents_of MODULE — the module and everything that needs it,
# transitively.
dependents_of() {
    local -A seen=()
    local -a todo=("$1")
    local module other dep
    while ((${#todo[@]})); do
        module=${todo[-1]}
        unset 'todo[-1]'
        if [[ -n ${seen[$module]-} ]]; then continue; fi
        seen[$module]=1
        printf '%s\n' "$module"
        for other in "${MOD_KEYS[@]}"; do
            for dep in ${MODULE_NEEDS[$other]-}; do
                if [[ $dep == "$module" ]]; then todo+=("$other"); fi
            done
        done
    done
}

# The starting selection: as in the repo, plus the required modules, minus
# what can't be installed (the secrets without the age key).
init_selection() {
    local module dep changed=1
    MOD_LOCKED=()
    for module in "${MOD_KEYS[@]}"; do
        MOD_ON[$module]=${MOD_REPO[$module]}
        if is_required "$module"; then MOD_ON[$module]=1; fi
    done
    if [[ -z $AGE_KEY && -n ${MOD_FILE[$SECRETS_MODULE]-} ]]; then
        while IFS= read -r module; do
            MOD_ON[$module]=0
            if [[ $module == "$SECRETS_MODULE" ]]; then
                MOD_LOCKED[$module]='no age key found'
            else
                MOD_LOCKED[$module]="needs $(short "$SECRETS_MODULE")"
            fi
        done < <(dependents_of "$SECRETS_MODULE")
    fi
    # Anything on whose dependency is off (a repo edited by hand) goes off.
    while ((changed)); do
        changed=0
        for module in "${MOD_KEYS[@]}"; do
            if [[ ${MOD_ON[$module]} == 0 ]]; then continue; fi
            for dep in ${MODULE_NEEDS[$module]-}; do
                if [[ -n ${MOD_FILE[$dep]-} && ${MOD_ON[$dep]} == 0 ]]; then MOD_ON[$module]=0 changed=1; fi
            done
        done
    done
}

# switch_module MODULE 0|1 [quiet] — switches it, along with whatever has to
# follow (what it needs, or what needs it).
switch_module() {
    local module=$1 want=$2 quiet=${3-} other blocker='' also=''
    local -a affected=()
    local -A switching=()
    if [[ $want == 1 ]]; then
        mapfile -t affected < <(needs_of "$module")
        # Blame the root cause: the module it needs that's locked, rather
        # than itself (locked only because of that one).
        for other in "${affected[@]}"; do
            if [[ -n ${MOD_LOCKED[$other]-} && ( -z $blocker || $blocker == "$module" ) ]]; then blocker=$other; fi
        done
        if [[ -n $blocker ]]; then
            if [[ -n $quiet ]]; then
                :
            elif [[ $blocker == "$module" ]]; then
                warn "$(short "$module") can't be installed: ${MOD_LOCKED[$module]}."
            else
                warn "$(short "$module") can't be installed: it needs $(short "$blocker") (${MOD_LOCKED[$blocker]})."
            fi
            return 0
        fi
    else
        mapfile -t affected < <(dependents_of "$module")
        for other in "${affected[@]}"; do
            if is_required "$other"; then
                [[ -n $quiet ]] || warn "$(short "$module") can't be left out: $(short "$other") needs it."
                return 0
            fi
        done
    fi
    for other in "${affected[@]}"; do
        if [[ ${MOD_ON[$other]} != "$want" ]]; then
            MOD_ON[$other]=$want
            if [[ $other != "$module" ]]; then switching[$other]=1; fi
        fi
    done
    [[ -z $quiet && ${#switching[@]} -gt 0 ]] || return 0
    for other in "${MOD_KEYS[@]}"; do
        if [[ -n ${switching[$other]-} ]]; then also+="${also:+, }$(short "$other")"; fi
    done
    if [[ $want == 1 && ${#switching[@]} == 1 ]]; then
        info "Also switched on, as $(short "$module") needs it: $also"
    elif [[ $want == 1 ]]; then
        info "Also switched on, as $(short "$module") needs them: $also"
    elif [[ ${#switching[@]} == 1 ]]; then
        info "Also switched off, as it needs $(short "$module"): $also"
    else
        info "Also switched off, as they need $(short "$module"): $also"
    fi
}

show_modules() {
    local module group='' n=0 box color desc width room required='' line
    width=$(tput cols 2>/dev/null) || width=100
    room=$((width - 40))
    for module in "${REQUIRED_MODULES[@]}"; do
        if [[ -n ${MOD_FILE[$module]-} ]]; then required+="${required:+, }$(short "$module")"; fi
    done
    printf '\n'
    while IFS= read -r line; do
        printf '    %s%s%s\n' "$DIM" "$line" "$RESET"
    done < <(fold -s -w "$((width > 30 ? width - 6 : 74))" <<<"Always installed: $required")
    PICK_KEYS=()
    for module in "${MOD_KEYS[@]}"; do
        if is_required "$module"; then continue; fi
        if [[ ${MOD_GROUP[$module]} != "$group" ]]; then
            group=${MOD_GROUP[$module]}
            printf '\n    %s%s%s\n' "$BOLD" "$group" "$RESET"
        fi
        n=$((n + 1))
        PICK_KEYS[n]=$module
        desc=${MOD_DESC[$module]-}
        if [[ -n ${MOD_LOCKED[$module]-} ]]; then
            box='[-]' color=$DIM desc=${MOD_LOCKED[$module]}
        elif [[ ${MOD_ON[$module]} == 1 ]]; then
            box='[x]' color=$GREEN
        else
            box='[ ]' color=$DIM
        fi
        if ((room < 10)); then
            desc=''
        elif ((${#desc} > room)); then
            desc="${desc:0:room-1}…"
        fi
        printf '  %3d %s%s%s %-28s %s%s%s\n' "$n" "$color" "$box" "$RESET" "$(short "$module")" "$DIM" "$desc" "$RESET"
    done
}

toggle_number() {
    local module=${PICK_KEYS[$1]-}
    if [[ -z $module ]]; then
        warn "There's no number $1."
    elif [[ ${MOD_ON[$module]} == 1 ]]; then
        switch_module "$module" 0
    else
        switch_module "$module" 1
    fi
}

pick_modules() {
    step "Modules for $HOST"
    info "Toggle modules by number (\"3 7-9\" works too); a = all, n = none, r = as in the repo, Enter = done."
    local reply token i
    local -a tokens
    while true; do
        show_modules
        printf '\n'
        read -rp "Toggle: " reply || die "No input, aborting."
        [[ -n $reply ]] || break
        read -ra tokens <<<"${reply//,/ }"
        for token in "${tokens[@]}"; do
            if [[ $token =~ ^([0-9]+)-([0-9]+)$ ]]; then
                for ((i = 10#${BASH_REMATCH[1]}; i <= 10#${BASH_REMATCH[2]}; i++)); do toggle_number "$i"; done
                continue
            elif [[ $token =~ ^[0-9]+$ ]]; then
                toggle_number "$((10#$token))"
                continue
            fi
            case $token in
                a | all) for i in "${!PICK_KEYS[@]}"; do switch_module "${PICK_KEYS[i]}" 1 quiet; done ;;
                n | none) for i in "${!PICK_KEYS[@]}"; do switch_module "${PICK_KEYS[i]}" 0 quiet; done ;;
                r | reset) init_selection ;;
                q | quit) die "Aborted; nothing was written." ;;
                *) warn "Not understood: $token" ;;
            esac
        done
    done
}

# Writes the selection into the machine's disabledModules, line by line:
# entries for modules now on are dropped (with the comment lines right
# above them), ones for modules now off are added at the end (with the
# reason, for the ones it can't install). Other comments, and entries for
# files that aren't in the catalog, stay as they are.
apply_modules() {
    local module file off='' known=''
    for module in "${MOD_KEYS[@]}"; do
        known+=$module$'\n'
        if [[ ${MOD_ON[$module]} == 0 ]]; then off+=$module$'\t'${MOD_LOCKED[$module]-}$'\n'; fi
    done
    file=$(host_file)
    OFF=$off KNOWN=$known awk '
        BEGIN {
            n = split(ENVIRON["OFF"], lines, "\n")
            for (i = 1; i <= n; i++) {
                if (lines[i] == "") continue
                split(lines[i], field, "\t")
                order[++count] = field[1]; want[field[1]] = 1; why[field[1]] = field[2]
            }
            n = split(ENVIRON["KNOWN"], lines, "\n")
            for (i = 1; i <= n; i++) if (lines[i] != "") known[lines[i]] = 1
        }
        function keep(module) { return !(module in known) || (module in want) }
        function flush_comments(   i) {
            for (i = 1; i <= held; i++) body[++lines_kept] = comments[i]
            held = 0
        }
        # The rebuilt list: what was kept, the entries still missing, and
        # "[ ];" if that leaves nothing.
        function close_list(   i) {
            for (i = 1; i <= count; i++)
                if (!(order[i] in present))
                    body[++lines_kept] = indent "  \"" order[i] "\"" (why[order[i]] != "" ? "  # " why[order[i]] : "")
            if (lines_kept == 0) { print indent "disabledModules = [ ];"; return }
            print indent "disabledModules = ["
            for (i = 1; i <= lines_kept; i++) print body[i]
            print indent "];"
        }
        state == 0 && /^[[:space:]]*disabledModules = \[/ {
            indent = $0; sub(/[^[:space:]].*$/, "", indent)
            if ($0 !~ /\];[[:space:]]*$/) { state = 1; next }
            # All on one line, e.g. "[ ];".
            rest = $0; sub(/^[^[]*\[/, "", rest); sub(/\];[[:space:]]*$/, "", rest)
            while (match(rest, /"[^"]*"/)) {
                module = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
                if (keep(module)) { body[++lines_kept] = indent "  \"" module "\""; present[module] = 1 }
            }
            close_list(); state = 2; next
        }
        state == 1 && /^[[:space:]]*\];/ { flush_comments(); close_list(); state = 2; next }
        # Comments are held until the next line shows whether the entry
        # they describe stays.
        state == 1 && /^[[:space:]]*#/ { comments[++held] = $0; next }
        state == 1 && /^[[:space:]]*"/ {
            module = $0; sub(/^[[:space:]]*"/, "", module); sub(/".*$/, "", module)
            if (keep(module)) { flush_comments(); body[++lines_kept] = $0; present[module] = 1 }
            else held = 0
            next
        }
        state == 1 { flush_comments(); body[++lines_kept] = $0; next }
        { print }
        END { if (state != 2) exit 1 }
    ' "$file" >"$WORK/variables.nix.new" || die "Couldn't find the disabledModules list in hosts/$HOST/variables.nix."
    cat "$WORK/variables.nix.new" >"$file"
}

# The modules left out, and any the machine had left out that are back.
module_changes() {
    local module off='' back=''
    for module in "${MOD_KEYS[@]}"; do
        if [[ ${MOD_ON[$module]} == 0 ]]; then
            off+="${off:+, }$(short "$module")"
        elif [[ ${MOD_REPO[$module]} == 0 ]]; then
            back+="${back:+, }$(short "$module")"
        fi
    done
    if [[ -z $off ]]; then off='none left out'; else off="left out: $off"; fi
    printf '%s%s\n' "$off" "${back:+; back in: $back}"
}

# --- Checks before the wipe ---

# Evaluates the whole system (home-manager included) without building it:
# anything that would make nixos-install fail at evaluation shows up now,
# before the disk is wiped. Also fetches the flake inputs it'll need anyway.
evaluate() {
    step "Evaluating the configuration"
    info "Nothing is written to any disk yet."
    local log=$WORK/eval.log
    fetch_inputs
    info "Evaluating every module (on the desktop, about 15s once the inputs are here; slower machines take longer):"
    if with_progress "evaluating" "$log" \
        nix eval --no-eval-cache --raw "$CONFIG_DIR#nixosConfigurations.\"$HOST\".config.system.build.toplevel.drvPath"; then
        ok "It evaluates ($(duration "$ELAPSED"))."
        return 0
    fi
    warn "It doesn't evaluate. The end of the error (all of it: $log):"
    grep -v '^warning:' "$log" | tail -n 30 | sed 's/^/    /' >&2 || true
    return 1
}

show_summary() {
    local note key=$AGE_KEY_FROM
    if [[ -z $RECIPIENTS ]]; then
        key='not needed'
    elif [[ -z $key ]]; then
        key="none: $(short "$SECRETS_MODULE") and what needs it are left out"
    fi
    step "Summary"
    printf '    %-9s %s\n' \
        Config "$SOURCE_DESC" \
        Machine "$HOST: $(describe_host "$HOST")" \
        User "$USERNAME" \
        Disk "${DISK:-none (dry run)}${DISK:+ ($DISK_DESC${DISK_HEALTH:+, SMART $DISK_HEALTH})}"
    if [[ -n $DISK_ID ]]; then printf '    %-9s → %s\n' "" "$DISK_ID"; fi
    printf '    %-9s %s\n' \
        "Age key" "$key" \
        Hardware "$HW_STATUS" \
        Modules "$(module_changes)"
    for note in "${NOTES[@]}"; do warn "$note"; done
}

confirm_wipe() {
    local reply
    printf '\n%s    ################################################################\n' "$RED$BOLD"
    printf '    EVERYTHING ON %s (%s) WILL BE ERASED:\n' "$DISK" "$DISK_DESC"
    printf '    ################################################################%s\n' "$RESET"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$DISK" | sed 's/^/    /'
    info "Right after this, disko asks for the LUKS passphrase (twice): you'll type it on every boot."
    info "Nothing else needs you until the end."
    reply=$(ask "Type YES to wipe the disk and install")
    [[ $reply == YES ]] || die "Aborted; nothing was written."
}

# --- Installing ---

# disko mounts the new system at TARGET, so whatever is there has to go,
# e.g. the stick, mounted by hand to get at this script. Lazily if it's busy
# (a shell sitting in it): the config is already in RAM.
free_install_root() {
    local target swap
    while IFS= read -r swap; do
        swapoff "$swap" 2>/dev/null || true
    done < <(awk -v target="$TARGET/" 'NR > 1 && index($1, target) == 1 { print $1 }' /proc/swaps)
    while IFS= read -r target; do
        target=$(unescape "$target")
        info "Unmounting $target"
        umount "$target" 2>/dev/null || umount -l "$target" || die "Couldn't unmount $target."
    done < <(findmnt -rn -o TARGET | grep -E "^$TARGET(/|\$)" | sort -r)
}

# Free space in the live ISO's Nix store (a RAM disk there), in MiB.
store_free_mib() { df -Pm /nix/store 2>/dev/null | awk 'NR == 2 { print $4 }'; }

run_disko() {
    local free
    step "Partitioning, encrypting and mounting $DISK (disko)"
    # disko as the config's flake builds it (its `disko` package): the
    # version flake.lock pins, same as its NixOS module in the config, and
    # built from the config's nixpkgs — on the repo's installer ISO,
    # already there, so nothing is downloaded into the ISO's RAM.
    # --yes-wipe-all-disks: the wipe was just confirmed above.
    until nix run "$CONFIG_DIR#disko" -- \
        --mode destroy,format,mount --yes-wipe-all-disks --root-mountpoint "$TARGET" --flake "$CONFIG_DIR#$HOST"; do
        free=$(store_free_mib)
        if [[ -n $free ]] && ((free < 200)); then
            die "disko failed: the live ISO's Nix store is out of space (${free} MiB left; it lives in RAM). $DISK wasn't touched if this happened while fetching disko. Boot the repo's installer ISO (prepare-usb.sh), which has disko and its tools built in, or a machine with more RAM."
        fi
        warn "disko failed. (A mistyped passphrase confirmation stops it too.)"
        confirm "Run it again?" y || die "Stopped after disko failed; $DISK may be partly wiped. Running this script again starts over."
    done
}

install_nixos() {
    local ram_gib cpus jobs=auto cores=0 tmp=${TARGET:?}/var/tmp/fresh-install
    step "Installing NixOS"
    info "It downloads several GiB and builds a few packages from source (the caelestia shell,"
    info "quickshell, Millennium, ...): on a laptop, allow an hour or more. Nix's status line"
    info "below moves as it goes; for a closer look, Alt+F2 opens another console"
    info "(top, free -h, df -h $TARGET). Ctrl+C stops it and offers to try again, keeping what's done."

    # Each parallel compile wants RAM, and the live ISO has nothing else:
    # below 16 GB, fewer at once (a 7.6 GB laptop gets one build of up to 4
    # threads) instead of the default of one per CPU, which can push it into
    # swapping for hours. Their temporary files go to the new disk, not RAM
    # (nixos-install's own default too, unless TMPDIR is already set).
    ram_gib=$(($(awk '/^MemTotal:/ { print $2 }' /proc/meminfo) / 1048576))
    cpus=$(nproc)
    if ((ram_gib < 16)); then
        jobs=$((ram_gib / 4 > 0 ? ram_gib / 4 : 1))
        cores=$((cpus < 4 ? cpus : 4))
        info "With ${ram_gib} GB of RAM: $jobs build(s) at a time, $cores thread(s) each."
    fi
    mkdir -p "$tmp"

    # Ctrl+C stops nixos-install, not this script: the loop then asks.
    trap ':' INT
    # --no-root-passwd: both passwords are set right after, from the hashes
    # asked for up front. --no-channel-copy: a flake system has no use for
    # the ISO's channel.
    until TMPDIR=$tmp nixos-install --flake "$CONFIG_DIR#$HOST" --root "$TARGET" \
        --no-root-passwd --no-channel-copy --max-jobs "$jobs" --cores "$cores"; do
        warn "nixos-install stopped or failed."
        if ! confirm "Try again? It keeps what's already downloaded and built." y; then
            trap 'exit 130' INT
            die "Stopped. The new system stays mounted at $TARGET: \`sudo fresh-install --resume\` carries on from here (until the live system reboots)."
        fi
    done
    trap 'exit 130' INT
    rm -rf "$tmp"
}

# What the steps after disko need, so `--resume` can carry on from
# nixos-install within the same live session: no questions, no wipe. Kept
# in RAM with the rest of the work files, root-only (the password hashes).
save_state() {
    local name
    (
        umask 077
        for name in HOST USERNAME DISK DISK_ID AGE_KEY AGE_KEY_FROM USER_HASH ROOT_HASH RECIPIENTS SRC_COPY CONFIG_DIR; do
            printf '%s=%q\n' "$name" "${!name-}"
        done >"$WORK/state"
    )
}

resume() {
    [[ -f $WORK/state ]] || die "Nothing to resume: no install got past partitioning in this live session (its state lives in RAM, so not across a reboot)."
    # shellcheck source=/dev/null
    source "$WORK/state"
    mountpoint -q "$TARGET" || die "$TARGET isn't mounted anymore, so there's nothing to resume; run fresh-install from the start."
    [[ -d $CONFIG_DIR ]] || die "$CONFIG_DIR is gone; run fresh-install from the start."
    step "Resuming the install of $HOST on $DISK"
    install_nixos
    set_passwords
    place_config
    carry_network_connections
    set_next_boot
    finish
}

set_passwords() {
    step "Setting the passwords"
    if printf '%s:%s\nroot:%s\n' "$USERNAME" "$USER_HASH" "$ROOT_HASH" | chpasswd --root "$TARGET" --encrypted; then
        ok "Set for $USERNAME and root."
        return 0
    fi
    warn "Couldn't set them from here; type them again:"
    until nixos-enter --root "$TARGET" -c "passwd $USERNAME"; do :; done
    until nixos-enter --root "$TARGET" -c "passwd root"; do :; done
}

place_config() {
    step "Putting the config in place"
    local home=$TARGET/home/$USERNAME owner
    mkdir -p "$TARGET/etc/nixos"
    cp -r "$CONFIG_DIR"/*.nix "$CONFIG_DIR"/modules "$CONFIG_DIR"/hosts "$TARGET/etc/nixos/"
    if [[ -d $CONFIG_DIR/secrets ]]; then cp -r "$CONFIG_DIR"/secrets "$TARGET/etc/nixos/"; fi
    # Its own lock file (docs/deploying.md): the one this install was built with.
    if [[ -f $CONFIG_DIR/flake.lock ]]; then cp "$CONFIG_DIR"/flake.lock "$TARGET/etc/nixos/"; fi
    ok "/etc/nixos: the deploy copy, as installed."

    owner=$(awk -F: -v user="$USERNAME" '$1 == user { print $3 ":" $4 }' "$TARGET/etc/passwd")
    if [[ -z $owner ]]; then
        warn "No user $USERNAME in the new system, so no ~/nixos."
        return 0
    fi
    if [[ ! -d $home ]]; then install -d -m 700 -o "${owner%:*}" -g "${owner#*:}" "$home"; fi
    mkdir -p "$home/nixos"
    cp -a "$SRC_COPY"/. "$home/nixos"/
    cp -a "$CONFIG_DIR"/. "$home/nixos"/
    chown -R "$owner" "$home/nixos"
    if [[ -d $SRC_COPY/.git ]]; then
        ok "/home/$USERNAME/nixos: the repo with its history; \`git status\` and \`git diff\` there show what this script changed."
    else
        ok "/home/$USERNAME/nixos: the repo as installed (the copy had no .git)."
    fi
}

# NetworkManager connections made in the ISO (the Wi-Fi joined above, say),
# so the new system is online from the first boot.
carry_network_connections() {
    local -a connections=(/etc/NetworkManager/system-connections/*.nmconnection) names
    ((${#connections[@]})) || return 0
    install -d -m 700 "$TARGET/etc/NetworkManager/system-connections"
    install -m 600 "${connections[@]}" "$TARGET/etc/NetworkManager/system-connections/"
    names=("${connections[@]##*/}")
    ok "Carried over network connections: ${names[*]%.nmconnection}"
}

# Makes the new install's boot entry the next boot (UEFI BootNext), so the
# reboot doesn't land in the ISO again if the stick is still in.
set_next_boot() {
    local esp partuuid entry
    command -v efibootmgr >/dev/null || return 0
    esp=$(findmnt -nro SOURCE "$TARGET/boot" 2>/dev/null) || return 0
    partuuid=$(lsblk -no PARTUUID "$esp" 2>/dev/null) || return 0
    [[ -n $partuuid ]] || return 0
    entry=$(efibootmgr -v 2>/dev/null | grep -i -- "$partuuid" | grep -oE '^Boot[0-9A-Fa-f]{4}' | head -n 1) || true
    [[ -n $entry ]] || return 0
    if efibootmgr -q -n "${entry#Boot}" 2>/dev/null; then ok "The next boot goes to the new install."; fi
}

unmount_install() {
    local crypt
    sync
    awk -v target="$TARGET/" 'NR > 1 && index($1, target) == 1 { print $1 }' /proc/swaps | while IFS= read -r swap; do swapoff "$swap" || true; done
    umount -R "$TARGET" 2>/dev/null || true
    lsblk -nrpo NAME,TYPE "$DISK" | awk '$2 == "crypt" { print $1 }' | while IFS= read -r crypt; do
        cryptsetup close "$crypt" 2>/dev/null || true
    done
}

finish() {
    step "Installed"
    rm -f "$WORK/age-key.txt"
    if [[ -z $AGE_KEY ]]; then
        warn "Without the age key, $(short "$SECRETS_MODULE") and what needs it were left out; docs/installing.md has how to add them back."
    fi
    info "Still to do after the first boot (docs/installing.md): restore /home, /persist and,"
    info "if you kept them, the Windows VM disk and Waydroid's data; then docs/manual-setup.md."
    if confirm "Reboot now?" y; then
        unmount_install
        info "Take the USB stick(s) out once the screen goes dark."
        reboot
    else
        info "Not rebooting. The new system is still mounted at $TARGET (nixos-enter --root $TARGET to look around)."
    fi
}

main() {
    parse_args "$@"
    setup
    printf '%sFresh NixOS install.%s Questions first; nothing is written to any disk until you type YES.\n' "$BOLD" "$RESET"
    if ((DRY_RUN)); then info "Dry run: it stops before touching any disk."; fi

    check_uefi
    check_memory
    check_network
    if ((RESUME)); then
        resume
        exit 0
    fi
    find_repo
    copy_source
    choose_host
    check_machine
    use_host_keymap
    find_age_key
    unmount_scans # the sticks aren't needed anymore
    choose_disk
    check_hardware_config

    load_modules
    init_selection
    pick_modules
    apply_modules
    if ((!DRY_RUN)); then
        step "Passwords"
        USER_HASH=$(new_password "Password for $USERNAME")
        if confirm "Same password for root (only used for console fallback logins)?" y; then
            ROOT_HASH=$USER_HASH
        else
            ROOT_HASH=$(new_password "Password for root")
        fi
    fi
    until evaluate; do
        confirm "Change the modules and evaluate again?" y || die "Aborted: the configuration doesn't evaluate. The patched copy is in $CONFIG_DIR."
        pick_modules
        apply_modules
    done
    hardware_notes
    show_summary

    if ((DRY_RUN)); then
        step "Dry run done"
        info "Stopped before touching any disk. The patched config is in $CONFIG_DIR."
        exit 0
    fi
    confirm_wipe
    free_install_root
    run_disko
    if [[ -n $AGE_KEY ]]; then
        install -D -m 0400 -o root -g root "$AGE_KEY" "$TARGET/var/lib/sops-nix/key.txt"
        ok "Age key installed to /var/lib/sops-nix/key.txt."
    fi
    save_state
    install_nixos
    set_passwords
    place_config
    carry_network_connections
    set_next_boot
    finish
}

# Only when run, not when sourced (e.g. to test single functions).
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
