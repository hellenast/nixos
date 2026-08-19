{ config, pkgs, lib, username, ... }:

{
  # --- Caelestia theming support ---
  # A couple of system-level things caelestia's dynamic theming needs that
  # have nothing to do with home-manager.

  # dconf: caelestia writes GTK theme/color-scheme/icon-theme keys with
  # `dconf write` on every theme switch. Without the D-Bus service actually
  # running, those writes go nowhere.
  programs.dconf.enable = true;

  # caelestia recolors Papirus folders on every scheme switch by shelling
  # out to `sudo -n papirus-folders -C <color> -u` (hardcoded in
  # caelestia-cli, not something I can change via cli.settings). Getting
  # this working took some digging, so the short version of why this is
  # here:
  #
  # - Since caelestia never passes `-u`, sudo always targets root no matter
  #   what the RunAs list allows (I tried restricting it to just me, to
  #   dodge the next problem — sudo simply refused to match at all without
  #   an explicit `-u`). Running as root resets $HOME to /root, and
  #   papirus-folders doesn't even read $HOME — it derives the theme
  #   owner's home from `id -nu`, i.e. root, unless $USER_HOME is already
  #   set in its environment. `env_keep` here preserves that across the
  #   sudo call; hypr-user.lua is what actually sets USER_HOME in the first
  #   place, since that's the environment caelestia's own subprocess calls
  #   inherit.
  # - Separately, sudo's command matching only ever worked against the
  #   *exact* path string it resolves the bare "papirus-folders" to — it
  #   doesn't seem to canonicalize through symlinks. Since I can't be sure
  #   which of my several PATH entries it actually picks, all three
  #   plausible candidates are listed so one is guaranteed to match: the
  #   real store path, the system profile symlink (added to
  #   environment.systemPackages below), and the home-manager per-user
  #   profile symlink.
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
    # Needs to resolve via sudo's own PATH search for the *bare* command
    # name caelestia's theme.py invokes — see security.sudo.extraRules
    # above for the full story on why /run/current-system/sw/bin matters.
    papirus-folders  # recolors Papirus folder icons on theme switch

    # papirus-folders itself shells out to `gtk-update-icon-cache` after
    # recoloring — same PATH-visibility problem one level down, since it
    # runs under the restricted PATH root gets via that sudo call.
    # Non-fatal without it (folder colors still change, just no cache
    # refresh), but having this makes the warning go away outright.
    gtk3  # provides gtk-update-icon-cache
  ];
}
