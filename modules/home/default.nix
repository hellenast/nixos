{ pkgs, username, cursorTheme, cursorSize, ... }:

# The user's home-manager config, entry point. Imported from flake.nix.
# Everything that's user-level only lives under here; features that also
# need system-level config keep both halves together in one NixOS module
# instead (desktop/thunar.nix, gaming/steam.nix, apps/amazfit.nix).
{
  imports = [
    ./caelestia.nix
    ./hyprland.nix
    ./terminal.nix

    ./apps/zen.nix
    ./apps/helium.nix
    ./apps/vscodium.nix
    ./apps/vesktop.nix
    ./apps/spotify.nix
    ./apps/zapzap.nix
    ./apps/media.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  # The home-manager release first used on this machine. Like the system's
  # stateVersion, don't bump it on upgrades.
  home.stateVersion = "26.11";

  # Writes ~/.config/user-dirs.dirs and creates the folders (Pictures,
  # Documents, Downloads, ...). Some apps, caelestia's wallpaper picker
  # included, look up the Pictures folder through this file and fail
  # without it.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    # A home-manager extra (not a real XDG dir) that would otherwise create
    # ~/Projects on every activation.
    projects = null;
  };

  # Cursor theme, from variables.nix. Bibata, because the dots' default
  # ("sweet-cursors") isn't packaged in nixpkgs. This covers GTK/X11 and icon
  # lookup; Hyprland/hyprcursor get it from hypr-user.lua
  # (home/hyprland.nix).
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = cursorTheme;
    size = cursorSize;
    gtk.enable = true;
    x11.enable = true;
  };

  home.packages = with pkgs; [
    bibata-cursors     # cursor theme (home.pointerCursor above)
    bitwarden-desktop  # password manager

    # Wine prefix manager, for Windows apps without a Linux build (Rave, so
    # far). Each app gets its own isolated prefix. The 32-bit graphics and
    # audio support Wine needs is already on for Steam (system/hardware.nix,
    # desktop/audio.nix).
    bottles
  ];

  # --- Keyboard: ' + c gives ç ---
  # Dead acute + c gives ć by default, on the desktop's US intl layout and
  # the laptops' ABNT2 alike (ABNT2 has its own ç key too). `include "%L"`
  # keeps every other sequence for the locale (á, ã, ü, ...) and overrides
  # just this one. Read by libxkbcommon on both X11 and Wayland.
  #
  # Known gap: Electron apps (VSCodium, Vesktop, Spotify) ignore
  # ~/.XCompose — they use a compose table built in from the standard locale
  # data — so they still give ć. Fixing that would need an input method
  # daemon (ibus/fcitx), which isn't worth it for one key.
  home.file.".XCompose".text = ''
    include "%L"

    <dead_acute> <c> : "ç" U00E7
    <dead_acute> <C> : "Ç" U00C7
  '';

  # Updates flake.lock (nixpkgs, home-manager, caelestia, browsers, ...) and
  # shows what changed. Deliberately doesn't deploy: a bad bump is worth
  # reviewing first, and deploying needs sudo anyway. Flatpaks update on
  # their own (desktop/flatpak.nix, home/apps/spotify.nix).
  home.file.".local/bin/update-flake.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      cd "$HOME/nixos"

      echo "Updating flake inputs..."
      nix flake update

      if [ -d .git ]; then
        echo
        echo "=== flake.lock changes ==="
        git --no-pager diff -- flake.lock || true
      fi

      echo
      echo "Review the changes above, then deploy with (see docs/deploying.md):"
      echo "  sudo rm -rf /etc/nixos/modules /etc/nixos/hosts && sudo cp -r ~/nixos/*.nix ~/nixos/modules ~/nixos/hosts ~/nixos/secrets /etc/nixos/ && cd /etc/nixos && sudo nixos-rebuild switch --flake .#"
    '';
  };
}
