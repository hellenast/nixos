{ config, pkgs, lib, inputs, ... }:

# caelestia-shell (bar, launcher, lock screen, notifications, wallpaper
# picker, ...) and caelestia-cli, which drives its dynamic theming: on every
# wallpaper/scheme change the CLI re-themes GTK/Qt, the terminal, Hyprland
# and so on, and renders the user templates in ~/.config/caelestia/templates.
#
# Per-app integrations live with each app (home/apps/*.nix,
# gaming/steam.nix) and plug in through that templates folder and the
# `caelestia.postHooks` option defined here. System-level pieces (fonts,
# dconf, sudo rule for papirus-folders) are in desktop/caelestia.nix.
let
  # Initial ~/.config/caelestia/shell.json. Seeded once instead of managed —
  # see seedCaelestiaShellConfig below.
  caelestiaShellSettings = {
    bar.scrollActions.brightness = false;
    # Which status icons show in the bar. The schema's `statusIcons` list
    # replaced the older `bar.status` object (an unknown key there is what
    # triggers the shell's "unknown config" notification). Reloads replace
    # the whole list rather than merging by id, so every default entry has
    # to be listed, even though only battery differs from its default.
    bar.statusIcons = [
      { id = "lockStatus"; enabled = true; }
      { id = "audio"; enabled = true; }
      { id = "microphone"; enabled = false; }
      { id = "kbLayout"; enabled = false; }
      { id = "network"; enabled = true; }
      { id = "bluetooth"; enabled = true; }
      { id = "battery"; enabled = false; }
    ];
    # Which modules show in the bar — same list shape, and the full default
    # list for the same reason.
    bar.entries = [
      { id = "logo"; enabled = true; }
      { id = "workspaces"; enabled = true; }
      { id = "spacer"; enabled = true; }
      { id = "activeWindow"; enabled = true; }
      { id = "spacer"; enabled = true; }
      { id = "tray"; enabled = true; }
      { id = "clock"; enabled = true; }
      { id = "statusIcons"; enabled = true; }
      { id = "power"; enabled = true; }
    ];
    osd.enableBrightness = false;
    # Celsius and 24-hour time regardless of locale (both default to a
    # locale-based guess).
    services.useFahrenheit = false;
    services.useTwelveHourClock = false;
  };
  caelestiaShellSettingsFile = pkgs.writeText "caelestia-shell-seed.json" (builtins.toJSON caelestiaShellSettings);

  # A Python interpreter that can import caelestia-cli's own modules (its
  # site-packages plus dependencies, the same set its wrapper loads), so
  # renderCaelestiaTemplates can call the CLI's real rendering code.
  caelestiaCliPython = let
    cli = config.programs.caelestia.cli.package;
    python = lib.findFirst (p: (p.pname or "") == "python3") pkgs.python3 cli.propagatedBuildInputs;
    modules = python.pkgs.requiredPythonModules (builtins.filter (p: p ? pythonModule) cli.propagatedBuildInputs);
  in pkgs.writeShellScript "caelestia-cli-python" ''
    export PYTHONPATH=${lib.makeSearchPath python.sitePackages ([ cli ] ++ modules)}
    exec ${python.interpreter} "$@"
  '';
in
{
  imports = [ inputs.caelestia-shell.homeManagerModules.default ];

  # The CLI has a single postHook string, run through a shell after every
  # scheme change. Modules add their own commands here instead, and they're
  # joined below. Each is started in the background, so a slow one can't
  # hold up the scheme change or the others.
  options.caelestia.postHooks = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Shell commands run in the background after every caelestia scheme change.";
  };

  config = {
    programs.caelestia = {
      enable = true;
      cli.enable = true;

      # The module would run the shell as a systemd user service tied to
      # graphical-session.target, but that target never activates here
      # (greetd execs Hyprland directly — see desktop/session.nix). The
      # shell really starts from the dots' hypr/hyprland/execs.lua
      # (`caelestia shell -d`), as a Hyprland child. So the unit would be
      # dead weight, and any env vars must be set through hl.env() in
      # hypr-user.lua (home/hyprland.nix) to reach the shell.
      systemd.enable = false;

      # Patched so the "Keep awake" toggle (utilities panel) actually stops
      # the shell's idle timeouts (lock at 3min, screen off at 5min, ...).
      #
      # Upstream, the toggle puts a Wayland idle inhibitor on an invisible
      # 0x0 window (services/IdleInhibitor.qml), and the IdleMonitors are
      # meant to respect it. But a 0x0 window never gets a buffer, so it's
      # never mapped, and Hyprland ignores inhibitors on unmapped surfaces
      # (recheckIdleInhibitorStatus() in src/managers/input/IdleInhibitor.cpp).
      # The toggle flips but nothing is inhibited; it only seemed to work
      # while media played, because general.idle.inhibitWhenAudio pauses
      # the timeouts then. The patch makes IdleMonitors check the toggle
      # directly. The import is qualified because IdleMonitors.qml also
      # imports Quickshell.Wayland, which has its own IdleInhibitor type.
      package = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace modules/IdleMonitors.qml \
            --replace-fail 'import qs.services' 'import qs.services
          import qs.services as Services' \
            --replace-fail 'readonly property bool enabled: {' 'readonly property bool enabled: {
                  if (Services.IdleInhibitor.enabled)
                      return false;'
        '';
      });

      # The module's `settings` option (shell.json) is deliberately unused —
      # see seedCaelestiaShellConfig below.

      # cli.json. The app modules add to this too: theme.enableDiscord and
      # toggles.communication (apps/vesktop.nix), theme.enableSpicetify and
      # toggles.music (apps/spotify.nix), theme.enableChromium
      # (apps/helium.nix).
      cli.settings = {
        theme = {
          enableTerm = true;
          enableHypr = true;
          enableFuzzel = true;
          enableBtop = true;
          enableGtk = true;
          enableQt = true;
          enableZed = false;  # Zed isn't installed
          iconTheme = "Papirus-Dark";
          iconThemeLight = "Papirus-Light";
          iconThemeDark = "Papirus-Dark";

          postHook = lib.concatMapStringsSep " " (hook: "${hook} &") config.caelestia.postHooks;
        };

        # The dots hardcode `foot` for the floating btop scratchpad
        # (Super + sysmon key). The dots' functions.lua merges this over its
        # defaults (load_toggle_config()/merge()), so overriding `command`
        # swaps in kitty with the same class/title/fish invocation.
        toggles.sysmon.btop = {
          command = [ "kitty" "--class" "btop" "-T" "btop" "fish" "-C" "exec btop" ];
        };
      };
    };

    # Wallpaper folder for the `caelestia` CLI and the shell's picker. Both
    # already default to this; it's set so every piece agrees explicitly.
    # Also set from Hyprland (home/hyprland.nix), since session variables
    # may not be loaded when Hyprland starts the shell.
    home.sessionVariables.CAELESTIA_WALLPAPERS_DIR = "${config.home.homeDirectory}/Pictures/Wallpapers";

    # caelestia recolours the Papirus folder icons on every scheme change,
    # but only in a writable copy of the theme — never the one in the Nix
    # store. This copies the theme into ~/.local/share/icons once, then
    # leaves it alone so papirus-folders' edits survive rebuilds.
    home.activation.seedPapirusIcons = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      dest="$HOME/.local/share/icons"
      if [ ! -d "$dest/Papirus" ]; then
        $DRY_RUN_CMD mkdir -p "$dest"
        for variant in Papirus Papirus-Dark Papirus-Light; do
          $DRY_RUN_CMD cp -r --no-preserve=mode "${pkgs.papirus-icon-theme}/share/icons/$variant" "$dest/$variant"
          $DRY_RUN_CMD chmod -R u+w "$dest/$variant"
        done
      fi
    '';

    # The shell's settings GUI writes its changes back to shell.json, so the
    # file has to be writable. The module's `settings` option would make it
    # a read-only symlink into the store, and every save (and every rebuild's
    # reload) failed with a "Failed to save config" toast. Instead, it's
    # seeded once from caelestiaShellSettings and then owned by the shell.
    #
    # Trade-off: changes to caelestiaShellSettings aren't picked up by
    # themselves — `rm ~/.config/caelestia/shell.json` and rebuild to reseed.
    home.activation.seedCaelestiaShellConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      dest="$HOME/.config/caelestia/shell.json"
      if [ ! -e "$dest" ]; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$dest")"
        $DRY_RUN_CMD cp --no-preserve=mode "${caelestiaShellSettingsFile}" "$dest"
        $DRY_RUN_CMD chmod u+w "$dest"
      fi
    '';

    # The CLI only renders ~/.config/caelestia/templates on a scheme change,
    # so a new or edited template would do nothing until the next wallpaper
    # change. This renders them once per activation from the current scheme,
    # using the CLI's own apply_user_templates() — the same output as a
    # scheme change, without re-applying everything else. Runs after
    # linkGeneration, once the template symlinks are in place. Non-fatal: if
    # a CLI update moves these functions, the next scheme change still
    # renders everything.
    home.activation.renderCaelestiaTemplates = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -f "${config.xdg.stateHome}/caelestia/scheme.json" ]; then
        $DRY_RUN_CMD ${caelestiaCliPython} -c 'from caelestia.utils.scheme import get_scheme; from caelestia.utils.theme import apply_user_templates; s = get_scheme(); apply_user_templates(s.colours, s.mode)' \
          || echo "renderCaelestiaTemplates: rendering failed; templates render on the next scheme change instead" >&2
      fi
    '';

    home.packages = with pkgs; [
      # Theming targets. adw-gtk3 is the GTK3 theme whose named colours
      # caelestia's generated gtk.css overrides — without it there's
      # nothing for that CSS to restyle.
      adw-gtk3            # GTK3 theme restyled by caelestia's gtk.css
      papirus-icon-theme  # icon theme (theme.iconTheme above)
      papirus-folders     # recolours Papirus folders (see desktop/caelestia.nix)

      # Tools the shell and CLI call directly.
      playerctl            # media control, for the bar/OSD media widgets
      brightnessctl        # backlight control, for the brightness OSD
      grim                 # screen capture, for `caelestia screenshot` and grimblast
      slurp                # region selection for screenshots
      cliphist             # clipboard history picker
      wl-clipboard         # wl-copy/wl-paste
      libnotify            # notify-send
      app2unit             # launches toggled apps
      gpu-screen-recorder  # backs `caelestia record`
    ];
  };
}
