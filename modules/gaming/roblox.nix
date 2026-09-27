{ ... }:

# Roblox through Sober, which runs the Android build of Roblox natively on
# Linux. Installed through desktop/flatpak.nix; Sober is also why Flatpaks
# update daily and on every boot there (it won't launch on a stale build).
{
  services.flatpak.packages = [
    "org.vinegarhq.Sober"
  ];

  services.flatpak.overrides = {
    "org.vinegarhq.Sober" = {
      Context = {
        # Raw input device access, e.g. for game controllers.
        devices = [ "input" ];
      };
    };
  };
}
