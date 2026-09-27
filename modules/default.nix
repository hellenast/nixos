# Every NixOS module this machine uses, grouped by area. To drop a feature,
# delete its line here (and the file, if you like) — see docs/modules.md for
# what each one does. Where a module depends on another one, it says so
# next to its line.
#
# The user's own desktop/apps/dotfiles (home-manager) live in ./home and are
# wired up in flake.nix, not here.
{
  imports = [
    # --- System: disk, boot, hardware, core services ---
    ./system/hardware-configuration.nix
    ./system/disko.nix
    ./system/boot.nix
    ./system/hardware.nix
    ./system/base.nix
    ./system/nix.nix
    ./system/memory.nix
    ./system/power.nix
    # Needed by network/protonvpn.nix. fresh-install.sh comments both out
    # for the first install, before the age key is in place.
    ./system/secrets.nix

    # --- Desktop session ---
    ./desktop/session.nix
    ./desktop/audio.nix
    ./desktop/caelestia.nix
    ./desktop/thunar.nix
    # Needed by apps/amazfit.nix and gaming/roblox.nix (Flatpak installs).
    ./desktop/flatpak.nix

    # --- Apps ---
    ./apps/dev.nix
    ./apps/ai.nix
    ./apps/amazfit.nix

    # --- Gaming ---
    ./gaming/steam.nix
    ./gaming/minecraft.nix
    ./gaming/roblox.nix
    # ALVR streams SteamVR, so this is only useful with gaming/steam.nix.
    ./gaming/vr.nix

    # --- VMs and containers ---
    ./virtualisation/windows-vm.nix
    # The virtual mic the Windows VM's voice changer feeds into.
    ./virtualisation/audio-routing.nix
    ./virtualisation/waydroid.nix

    # --- Network ---
    ./network/protonvpn.nix
    ./network/tor.nix
  ];
}
