{ pkgs, ... }:

# Waydroid: a real Android system in an LXC container (GPU-accelerated, not
# an emulator or a reimplementation), for Android apps with no Linux build.
# Not tied to any one app right now. It was set up for Minecraft Bedrock,
# which crashes in it (docs/gaming.md), but it's kept for other apps.
#
# This only provides the container runtime. Initialising Android, signing
# into Google, and the fixed-resolution workaround for the window not
# resizing are all done interactively — see docs/virtualisation.md.
#
# Android's own state (installed apps, their data, accounts) lives in
# /var/lib/waydroid/data on the root subvolume, outside /home and /persist,
# so a reformat wipes it. That directory is the only one worth backing up
# (docs/installing.md).
{
  virtualisation.waydroid.enable = true;

  # The default package's network setup (waydroid-net.sh) uses legacy
  # iptables, which needs the `ip_tables` kernel module — this kernel only
  # has nf_tables, so the container failed to start ("Failed to setup
  # waydroid-net" in waydroid.log). waydroid-nftables is the same package
  # driving `nft` instead. The module only picks it automatically with
  # `networking.nftables.enable = true`, and switching the whole system's
  # firewall backend just for this isn't worth it.
  virtualisation.waydroid.package = pkgs.waydroid-nftables;
}
