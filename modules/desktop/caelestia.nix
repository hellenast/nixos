{ pkgs, username, ... }:

# The system-level pieces caelestia-shell needs that home-manager can't
# provide. The shell itself and its theming are in home/caelestia.nix.
{
  # Fonts the shell's UI is built with.
  fonts.packages = with pkgs; [
    material-symbols  # icon glyphs used throughout the UI
    rubik             # UI text font
  ];

  # caelestia applies the GTK theme, colour scheme and icon theme with
  # `dconf write` on every scheme change; without the dconf D-Bus service
  # those writes go nowhere.
  programs.dconf.enable = true;

  # On every scheme change, caelestia-cli recolours the Papirus folder icons
  # by running `sudo -n papirus-folders -C <colour> -u` (hardcoded; there is
  # no setting for it). Making that work without a password prompt takes
  # two things:
  #
  # - Keeping USER_HOME. caelestia never passes `sudo -u`, so the command
  #   runs as root, and papirus-folders then works out the icon theme's
  #   owner from `id -nu` — root — unless USER_HOME is set. home/hyprland.nix
  #   sets USER_HOME in the session; env_keep passes it through sudo.
  #   (Restricting the rule to run as my own user doesn't work: without
  #   `-u` in the call, sudo won't match it at all.)
  #
  # - Matching the exact path. sudo matches the command against the path it
  #   resolves "papirus-folders" to on PATH, without following symlinks.
  #   Which PATH entry wins isn't fixed, so all three places the binary can
  #   be found are allowed: the store path itself, the system profile
  #   (installed below) and the per-user profile (home/caelestia.nix).
  security.sudo.extraConfig = ''
    Defaults:${username} env_keep += "USER_HOME"
  '';
  security.sudo.extraRules = [
    {
      users = [ username ];
      commands = map (cmd: { command = cmd; options = [ "NOPASSWD" ]; }) [
        "${pkgs.papirus-folders}/bin/papirus-folders"
        "/run/current-system/sw/bin/papirus-folders"
        "/etc/profiles/per-user/${username}/bin/papirus-folders"
      ];
    }
  ];

  environment.systemPackages = with pkgs; [
    # In the system profile so the bare command name resolves through
    # sudo's PATH (see above).
    papirus-folders  # recolours Papirus folder icons

    # papirus-folders runs `gtk-update-icon-cache` afterwards, under root's
    # restricted PATH. Without it, recolouring still works but prints a
    # warning and skips the cache refresh.
    gtk3  # provides gtk-update-icon-cache
  ];
}
