{ pkgs, inputs, keyboardLayout, keyboardVariant, primaryMonitor, secondaryMonitor, cursorTheme, cursorSize, ... }:

# Hyprland's user config: the caelestia dots' config as the base, my
# overrides on top (hypr-user.lua), and the screenshot scripts bound there.
# Hyprland itself and the login flow are system-level, in
# desktop/session.nix.
let
  dots = inputs.caelestia-dots-src;

  # The dots' Hyprland config, with one patch to rules.lua: Vesktop is
  # dropped from the "communication_app" tag, whose rule sends those windows
  # to a special, screen-covering workspace. Vesktop should tile like a
  # normal window. (Discord/Equibop keep the tag, and WhatsApp has its own
  # untouched entry.)
  #
  # It has to be patched at the source because the workspace is decided
  # when the window is created: removing the tag from hypr-user.lua, which
  # loads later, does clear the tag but not the workspace. And it has to be
  # a patched copy of the whole tree because a separate xdg.configFile entry
  # for just rules.lua loses to the recursive "hypr" entry's own symlink.
  #
  # A targeted string replace rather than a vendored copy of rules.lua, so
  # upstream changes to the rest of the file still come through.
  hyprDotsPatched = pkgs.runCommand "hypr-dots-patched" { } ''
    cp -r --no-preserve=mode ${dots}/hypr $out
    cp ${
      pkgs.writeText "rules.lua" (
        builtins.replaceStrings
          [ ''"discord|equibop|vesktop"'' ]
          [ ''"discord|equibop"'' ]
          (builtins.readFile "${dots}/hypr/hyprland/rules.lua")
      )
    } $out/hyprland/rules.lua
  '';
in
{
  xdg.configFile."hypr" = {
    source = hyprDotsPatched;
    recursive = true;
  };

  # No hypridle config: idle, lock and screen-off are handled by
  # caelestia-shell itself (modules/IdleMonitors.qml, and its session
  # manager listening to logind), and nothing in the dots runs hypridle.

  # My overrides. caelestia's Hyprland config loads this file last, for
  # exactly this purpose, and `caelestia update` never overwrites it.
  #
  # This is the Lua config format (Hyprland 0.55+). If the dots ever go back
  # to hyprlang, the equivalent is caelestia/hypr-user.conf, e.g.:
  #   input {
  #       kb_layout  = us
  #       kb_variant = intl
  #   }
  xdg.configFile."caelestia/hypr-user.lua".text = ''
    hl.config({
      input = {
        kb_layout = "${keyboardLayout}",
        kb_variant = "${keyboardVariant}",
      },
    })

    -- Environment for everything Hyprland starts, including the caelestia
    -- shell. Set here because greetd execs Hyprland without a login shell,
    -- so home-manager's session variables may not be loaded yet.
    --
    -- Cursor theme for Wayland/hyprcursor clients (home.pointerCursor
    -- covers GTK/X11).
    hl.env("XCURSOR_THEME", "${cursorTheme}")
    hl.env("XCURSOR_SIZE", "${toString cursorSize}")

    -- Wallpaper folder (see home/caelestia.nix).
    hl.env("CAELESTIA_WALLPAPERS_DIR", os.getenv("HOME") .. "/Pictures/Wallpapers")

    -- Read by papirus-folders when caelestia runs it through sudo as root
    -- to recolour folders, so it finds my icon theme instead of root's.
    -- The sudo side (env_keep) is in desktop/caelestia.nix.
    hl.env("USER_HOME", os.getenv("HOME"))

    -- Monitor layout, from variables.nix: primary on the left at its full
    -- refresh rate, secondary to its right. Without this, Hyprland picks
    -- its own defaults whenever outputs re-enumerate (e.g. after the
    -- screen turns off), reverting the refresh rate or swapping sides.
    hl.monitor({
      output = "${primaryMonitor.output}",
      mode = "${primaryMonitor.mode}",
      position = "${primaryMonitor.position}",
      scale = 1,
    })
    hl.monitor({
      output = "${secondaryMonitor.output}",
      mode = "${secondaryMonitor.mode}",
      position = "${secondaryMonitor.position}",
      scale = 1,
      transform = ${toString secondaryMonitor.transform},
    })

    -- No lock screen on session start: greetd logs in automatically, and
    -- the LUKS passphrase at boot already gates access.
    hl.on("hyprland.start", function()
      -- The dots' execs.lua runs `hyprctl setcursor sweet-cursors 24` on
      -- start — a theme that isn't installed, and a hardcoded call no env
      -- var overrides. This file's handler runs after it, and the last
      -- setcursor wins. The sleep is slack, since exec_cmd doesn't block.
      hl.exec_cmd("sleep 1 && hyprctl setcursor ${cursorTheme} ${toString cursorSize} "
        .. "&& gsettings set org.gnome.desktop.interface cursor-theme ${cursorTheme} "
        .. "&& gsettings set org.gnome.desktop.interface cursor-size ${toString cursorSize}")
    end)

    -- Screenshots. The dots bind Print (and Super+Shift+S,
    -- Super+Shift+Alt+S) to `caelestia screenshot`, which only keeps the
    -- file if "Save" is clicked on its notification (otherwise it stays in
    -- ~/.cache). Replaced with scripts that always save to
    -- ~/Pictures/Screenshots:
    --   Print         -> freeze the screen, select a region, annotate in
    --                    Drawing, then save + copy + notify
    --   Shift + Print -> full screen, saved + copied + notified at once
    --
    -- hl.unbind matches by key combo only, so it must run before binding
    -- the same keys again, or it would remove the new binds too.
    hl.unbind("Print")
    hl.unbind("SUPER + SHIFT + S")
    hl.unbind("SUPER + SHIFT + ALT + S")
    hl.bind("Print", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/screenshot-region.sh"))
    hl.bind("SHIFT + Print", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/screenshot-full.sh"))

    -- Terminal: kitty instead of the dots' foot. The dots' Super+T bind
    -- captured vars.terminal when it was created, so changing the variable
    -- now wouldn't affect it — it has to be unbound and bound again.
    hl.unbind("SUPER + T")
    hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))

    -- kitty is deliberately not tagged "+opaque" (see home/terminal.nix).
    -- Drawing isn't tagged "+float" either: only the screenshot-annotation
    -- window should float, and a class rule can't tell it apart, so
    -- screenshot-region.sh floats just the window it opens.
  '';

  # --- Screenshot scripts (bound above) ---

  home.packages = [
    pkgs.grimblast  # freeze-then-select screenshots (via hyprpicker)
    # Drawing, used for annotation, is installed in home/apps/media.nix.
  ];

  home.file.".local/bin/screenshot-full.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      mkdir -p "$HOME/Pictures/Screenshots"
      file="$HOME/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
      grimblast save screen "$file" >/dev/null
      wl-copy < "$file"
      notify-send -i "$file" "Screenshot saved" "$file"
    '';
  };

  home.file.".local/bin/screenshot-region.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      mkdir -p "$HOME/Pictures/Screenshots"
      file="$HOME/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
      # --freeze shows a still image of the screen while selecting, so
      # nothing moves mid-drag. Pressing Escape exits non-zero, which ends
      # the script here (set -e).
      grimblast --freeze save area "$file" >/dev/null

      # Open Drawing floating, for this one window only (a class rule would
      # float every Drawing window). Under the Lua config, the old
      # `hyprctl dispatch exec "[float] ..."` syntax silently fails; calling
      # exec_cmd with its rules parameter through `hyprctl eval` works.
      # exec_cmd doesn't wait, so wait for Drawing to start, then to exit,
      # before copying and notifying.
      hyprctl eval "hl.dispatch(hl.dsp.exec_cmd('drawing $file', { float = true }))"
      for _ in $(seq 1 50); do
        pgrep -f "$file" >/dev/null 2>&1 && break
        sleep 0.1
      done
      while pgrep -f "$file" >/dev/null 2>&1; do
        sleep 0.5
      done

      [ -f "$file" ] && wl-copy < "$file" && notify-send -i "$file" "Screenshot saved" "$file"
    '';
  };
}
