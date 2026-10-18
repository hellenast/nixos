{ pkgs, username, ... }:

# The graphical session: Hyprland, auto-login into it, portals and polkit.
# Hyprland's own config (keybinds, monitors, rules) is user-level, in
# home/hyprland.nix.
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # greetd starts Hyprland directly, with no greeter and no password of its
  # own: the LUKS passphrase (system/disko.nix) already gates the machine at boot,
  # so a second prompt would be redundant.
  #
  # Side effect worth knowing: Hyprland is exec'd without a login shell or
  # session manager, so graphical-session.target never activates and
  # home-manager's session variables may not be loaded yet. That's why
  # several things are set again from Hyprland itself (home/hyprland.nix)
  # and why the caelestia shell isn't a systemd unit (home/caelestia.nix).
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "start-hyprland";
        user = username;
      };
      # Used after logging out of the initial session.
      default_session = {
        command = "start-hyprland";
        user = username;
      };
    };
  };

  # Portals: how sandboxed/Wayland apps ask for screen sharing, screenshots
  # and file pickers.
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland  # screen sharing, screenshot picker
      pkgs.xdg-desktop-portal-gtk       # file pickers and other common dialogs
    ];
    config.common.default = "*";
  };

  # Polkit. Its GUI agent, which answers the password prompts (e.g. from
  # NetworkManager, virt-manager or GNOME Disks), is polkit-gnome, started
  # by the dots' execs.lua as a Hyprland child (path patched in
  # home/hyprland.nix). Not a systemd user unit: those hang off
  # graphical-session.target, which never activates here.
  security.polkit.enable = true;
}
