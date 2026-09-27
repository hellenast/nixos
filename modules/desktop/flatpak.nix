{ pkgs, inputs, ... }:

# System-wide Flatpak, managed declaratively through nix-flatpak. The apps
# themselves are declared by the modules that use them
# (services.flatpak.packages): Sober in gaming/roblox.nix, Amazfish in
# apps/amazfit.nix. Spotify is a separate, user-scope install
# (home/apps/spotify.nix).
{
  imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

  services.flatpak.enable = true;

  services.flatpak.remotes = [
    {
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }
  ];

  # Flatpak apps aren't pinned by flake.lock, so they need their own
  # updater. Daily rather than weekly because Sober refuses to launch at all
  # on an outdated build, and Roblox ships new ones often.
  services.flatpak.update.auto = {
    enable = true;
    onCalendar = "daily";
  };

  # Also update on every boot, since even a same-day gap can leave Sober
  # stale. Independent of the timer above, whose unit is a nix-flatpak
  # internal.
  #
  # Deliberately not ordered after flatpak-managed-install.service: that
  # unit runs after multi-user.target, so ordering after it while being
  # WantedBy multi-user.target is a cycle, and systemd breaks it by silently
  # dropping this service from the boot.
  systemd.services.flatpak-update-on-boot = {
    description = "Update Flatpak apps on boot";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.flatpak}/bin/flatpak update --system -y";
  };
}
