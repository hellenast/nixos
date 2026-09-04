{ config, pkgs, lib, ... }:

{
  # Runs a real Android container via a full Android runtime (not a
  # reimplementation of one), so any Android app I can't get a native Linux
  # build of just works, GPU-accelerated, same as on a phone. First used to
  # get Minecraft Bedrock Edition running after mcpelauncher-ui-qt (an
  # unofficial reimplementation of Android's dynamic linker for loading
  # Bedrock's native .so files directly on Linux) turned out to be broken —
  # it segfaults on every Bedrock version I tested, since its custom symbol
  # resolver is missing libc symbols (pthread_sigmask, confirmed present in
  # this system's own glibc via nm/readelf, so the gap is in mcpelauncher's
  # own shim, not the host) that current Bedrock builds need. Not gaming-
  # specific though, so it lives in its own file rather than gaming.nix.
  # See Manual setup in README.md for the interactive `waydroid
  # init`/Play Store steps this still needs.
  #
  # This module only gets me the container itself back on a fresh install
  # (`waydroid init -s GAPPS`, freely redone from scratch every time). What
  # it does NOT get back is what's actually inside the container — apps,
  # their data, signed-in accounts — since that lives on the root btrfs
  # subvolume at /var/lib/waydroid/data, outside both /home and /persist
  # (see disko.nix), so a reformat wipes it just like it wipes the Windows
  # VM disk. I only need to back up that one `data` directory, not the
  # sibling `images`/`rootfs` dirs (just the downloaded Android build,
  # redone for free). See "Reinstalling with full-disk encryption" in
  # README.md for the actual backup/restore steps.
  virtualisation.waydroid.enable = true;

  # The default `waydroid` package's network setup script
  # (waydroid-net.sh) shells out to legacy `iptables`, which needs the
  # `ip_tables` kernel module to actually apply rules — this kernel doesn't
  # ship it (only the modern nf_tables, which IS loaded), so container
  # startup failed every time at "Failed to setup waydroid-net"
  # (`modprobe: FATAL: Module ip_tables not found`, then `iptables ...
  # Table does not exist`, in waydroid.log). waydroid-nftables is the same
  # package built to drive `nft` instead (confirmed via `strings` on its
  # waydroid-net.sh: it PATHs in nftables, not iptables), which works
  # against nf_tables directly. The module would pick this automatically
  # if I had `networking.nftables.enable = true` system-wide, but I don't
  # (configuration.nix still runs the classic firewall), so it's set
  # explicitly here instead of flipping the whole system's firewall
  # backend just for this.
  virtualisation.waydroid.package = pkgs.waydroid-nftables;
}
