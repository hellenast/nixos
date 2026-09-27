{ inputs, pkgs, ... }:

# Spotify, themed by spicetify with the caelestia dots' theme.
#
# Installed as a user-scope Flatpak (~/.local/share/flatpak) because
# spicetify patches Spotify's files in place: neither the Nix store nor a
# system-wide Flatpak (root-owned /var/lib/flatpak) is writable by the user.
# First-run spicetify setup is manual — see docs/theming.md.
{
  imports = [ inputs.nix-flatpak.homeManagerModules.nix-flatpak ];

  services.flatpak = {
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];
    # Installed on every home-manager activation (nix-flatpak's install
    # doesn't depend on graphical-session.target, which never activates in
    # this setup).
    packages = [ "com.spotify.Client" ];
    # An update overwrites Spotify's files, undoing spicetify's patch until
    # the next `spicetify apply` — which the scheme-change hook below runs.
    # If Spotify looks unthemed right after an update, change the wallpaper
    # once or run `spicetify apply`.
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };

  home.packages = [ pkgs.spicetify-cli ];

  # The "caelestia" spicetify theme. The CLI writes its colours on every
  # scheme change (theme.enableSpicetify below).
  xdg.configFile."spicetify/Themes/caelestia" = {
    source = "${inputs.caelestia-dots-src}/spicetify/Themes/caelestia";
    recursive = true;
  };

  programs.caelestia.cli.settings = {
    theme.enableSpicetify = true;

    # The music scratchpad toggle.
    toggles.music.spotify = {
      enable = true;
      # "spotify" is the window class the Flatpak build reports. The
      # matcher checks containment, not equality, so "Spotify" also catches
      # titles like "Spotify Premium".
      match = [{ class = "spotify"; } { initialTitle = "Spotify"; }];
      # A plain launch, no `spicetify watch` (see the hook below).
      command = [ "flatpak" "run" "com.spotify.Client" ];
      move = true;
    };
  };

  # Colours can't sync live: `spicetify watch` restarts Spotify by exec'ing
  # its binary directly, which crashes outside the Flatpak sandbox. Instead,
  # this re-patches Spotify with the new colours on every scheme change,
  # without touching a running Spotify — restart it to see the new theme.
  # (Restarting it automatically also launched Spotify when it wasn't
  # running.)
  caelestia.postHooks = [ "$HOME/.local/bin/caelestia-spotify-resync.sh" ];

  # Guarded by a lock (atomic mkdir, not a racy touch+test) so rapid scheme
  # changes — a light/dark toggle, a wallpaper slideshow — can't pile up
  # overlapping applies.
  home.file.".local/bin/caelestia-spotify-resync.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -uo pipefail

      lock="''${XDG_RUNTIME_DIR:-/tmp}/caelestia-spotify-resync.lock"
      mkdir "$lock" 2>/dev/null || exit 0
      trap 'rmdir "$lock"' EXIT

      spicetify apply >/dev/null 2>&1
    '';
  };
}
