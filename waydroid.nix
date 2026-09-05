{ config, pkgs, lib, ... }:

{
  # Runs a real Android container via a full Android runtime (not a
  # reimplementation of one), so any Android app I can't get a native Linux
  # build of just works, GPU-accelerated, same as on a phone. Not gaming-
  # specific, so it lives in its own file rather than gaming.nix.
  #
  # I originally set this up to get Minecraft Bedrock Edition running,
  # after mcpelauncher-ui-qt (an unofficial reimplementation of Android's
  # dynamic linker for loading Bedrock's native .so files directly on
  # Linux) turned out to be broken — it segfaults on every Bedrock version
  # I tested, since its custom symbol resolver is missing libc symbols
  # (pthread_sigmask, confirmed present in this system's own glibc via
  # nm/readelf, so the gap is in mcpelauncher's own shim, not the host)
  # that current Bedrock builds need. Waydroid got further (the container
  # itself runs fine), but Bedrock turned out to be broken here too — a
  # confirmed-fresh install (new UID, new package path) still crashes
  # instantly with SIGSEGV in libpairipcore.so, Mojang's own anti-tamper
  # library, which appears to actively refuse to run in Waydroid's
  # userdebug/test-keys LineageOS build (see waydroid/waydroid#2143
  # upstream, an open, unresolved report of the same crash on unrelated
  # hardware). Bedrock now runs through bedrock-on-linux instead (the real
  # Windows GDK build under steam-run/Proton, no Android layer at all —
  # see gaming.nix and flake.nix). Keeping this module around anyway: it's
  # genuinely useful for other Android apps, just not this one.
  #
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

  # Not declared here: the fixed-resolution workaround for the window not
  # resizing (Waydroid's single-window mode renders to one fixed-size
  # virtual display, and its multi-window mode — meant to give each app a
  # real resizable window instead — is broken on Hyprland specifically, per
  # open upstream reports on both projects' trackers). That's an Android
  # system property (`waydroid prop set persist.waydroid.width/height`),
  # set through the running container, not something this module can
  # express — see Manual setup in README.md for the actual commands.
}
