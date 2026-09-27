# Every NixOS module, grouped by area — see docs/modules.md for what each
# one does. Every machine gets all of them, except the ones its
# hosts/<name>/variables.nix lists in disabledModules (docs/machines.md).
# Where a module depends on another one, it says so next to its line;
# fresh-install.sh's module picker follows the same dependencies
# (MODULE_NEEDS there), so a new one goes in both places.
#
# The user's own desktop/apps/dotfiles (home-manager) live in ./home and are
# wired up in flake.nix, not here, as is each machine's
# hosts/<name>/hardware-configuration.nix.
{
  imports = [
    # --- System: disk, boot, hardware, core services ---
    ./system/disko.nix
    ./system/boot.nix
    ./system/gpu.nix
    ./system/hardware.nix
    ./system/base.nix
    ./system/nix.nix
    ./system/memory.nix
    ./system/power.nix
    # Needed by network/protonvpn.nix. fresh-install.sh leaves both out if
    # it can't find the age key (docs/installing.md).
    ./system/secrets.nix

    # --- Desktop session ---
    ./desktop/session.nix
    ./desktop/audio.nix
    ./desktop/caelestia.nix
    ./desktop/thunar.nix
    # Needed by apps/amazfit.nix, gaming/roblox.nix and home/apps/spotify.nix
    # (Flatpak installs; nix-flatpak's user-scope one still needs this).
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
    # The virtual mic the Windows VM's voice changer feeds into. Goes
    # together with windows-vm.nix, and needs desktop/audio.nix's PipeWire.
    ./virtualisation/audio-routing.nix
    ./virtualisation/waydroid.nix

    # --- Network ---
    ./network/protonvpn.nix
    # Its launcher runs Vesktop, from home/apps/vesktop.nix.
    ./network/tor.nix
  ];
}
