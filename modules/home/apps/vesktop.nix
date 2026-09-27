{ pkgs, lib, ... }:

# Vesktop, a Discord client with Vencord built in, themed by caelestia.
# The theme has to be enabled once by hand in Vesktop — see
# docs/theming.md. It's kept out of the dots' communication scratchpad (a
# patched rules.lua in home/hyprland.nix, and the toggle below), so it
# tiles like any other window.
{
  home.packages = with pkgs; [
    vesktop
    dart-sass  # the CLI compiles the Discord theme's SCSS with it
  ];

  programs.caelestia.cli.settings = {
    # Writes the theme to ~/.config/vesktop/themes/caelestia.theme.css on
    # every scheme change.
    theme.enableDiscord = true;

    # Disabled so Super+D (and anything else using the dots' "communication"
    # toggle) doesn't spawn or move Vesktop onto a special workspace
    # (place_apps() in the dots' functions.lua). Super+D now does nothing.
    toggles.communication.discord = {
      enable = false;
      match = [{ class = "vesktop"; }];
      command = [ "vesktop" ];
      move = true;
    };
  };

  # Vesktop saves its window state, including `maximized`, in state.json
  # every time it closes, and asks to be maximized again on launch. On
  # Hyprland that makes it cover the screen instead of tiling. Resetting
  # just that field on every activation keeps it tiled.
  home.activation.unmaximizeVesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.config/vesktop/state.json"
    if [ -e "$dest" ]; then
      $DRY_RUN_CMD ${pkgs.jq}/bin/jq '.maximized = false' "$dest" > "$dest.tmp" \
        && $DRY_RUN_CMD mv "$dest.tmp" "$dest"
    fi
  '';
}
