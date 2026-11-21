{ pkgs, username, ... }:

# OpenRazer + Polychromatic: lighting for Razer devices, here the Tartarus
# Pro keypad. OpenRazer is a set of kernel drivers plus a per-user daemon
# that talks to them; Polychromatic is its GUI (in the launcher as
# "Polychromatic"). The keypad's keys are input-remapper.nix's job, not
# this one's: the driver leaves the keypad's key reports alone, and the
# daemon only reads them (for the Ripple effect) without grabbing them.
#
# The Viper V3 Pro SE mouse (USB 1532:00df) isn't supported by this
# OpenRazer version (3.12.4 only knows the plain Viper V3 Pro), so no driver
# binds to it and neither app shows it. See docs/gaming.md.
{
  # The razerkbd/razermouse/... kernel modules, their udev rules, the
  # daemon (a user service) and the `openrazer` group that may use it. The
  # daemon refuses to start for anyone outside the group, which is why it
  # needs a new login after the first deploy.
  hardware.openrazer = {
    enable = true;
    users = [ username ];
  };

  # nixpkgs starts the daemon with graphical-session.target, which never
  # activates here (desktop/session.nix). D-Bus would still start it when
  # Polychromatic opens, but the daemon is also what puts back the lighting
  # it saved, after a reboot or a replug. So it starts at login instead.
  systemd.user.services.openrazer-daemon.wantedBy = [ "default.target" ];

  home-manager.users.${username}.home.packages = [ pkgs.polychromatic ];
}
