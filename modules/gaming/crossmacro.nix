{ config, pkgs, lib, username, ... }:

# CrossMacro: a GUI macro recorder/player and autoclicker that works on
# Wayland. Record mouse/keyboard input or build macros in its editor, then
# replay them with loops, delays, global hotkeys or schedules. Plus a
# Roblox anti-AFK toggle built on it — see docs/gaming.md.
#
# On Wayland, apps can't inject input themselves, so a root-started daemon
# (crossmacro.service, its own service user) owns a virtual uinput device.
# The app and CLI talk to it over a socket only members of the `crossmacro`
# group can use, which is why it needs a new login after the first deploy.
let
  # --- Roblox anti-AFK settings ---
  # Roblox disconnects after 20 minutes without input. caelestia locks the
  # screen after 3 minutes idle, and a locked screen takes the keyboard away
  # from Roblox, so the interval stays below that. The simulated key counts
  # as activity, which keeps the screen from locking.
  antiAfkInterval = 120; # seconds
  # A jump: harmless in nearly every game. Any key name CrossMacro knows
  # (`crossmacro run --help`), e.g. "W" or "E".
  antiAfkKey = "Space";
  # Sober's window class (`hyprctl clients`).
  soberClass = "org.vinegarhq.Sober";

  # The loop, run by the roblox-anti-afk user service below. It presses the
  # key only while Roblox is the focused window and the screen is unlocked,
  # so it never types into another app or the lock screen's password field.
  # It stops by itself once Roblox closes.
  antiAfkLoop = pkgs.writeShellApplication {
    name = "roblox-anti-afk-loop";
    runtimeInputs = [
      config.services.crossmacro.package
      config.programs.hyprland.package # hyprctl
      pkgs.jq
      pkgs.libnotify
      # `caelestia` (for the lock state) comes from the user's PATH.
    ];
    text = ''
      notify() {
        notify-send -a "Roblox anti-AFK" -i ${soberClass} "$@"
      }

      roblox_running() {
        hyprctl clients -j | jq -e --arg class ${soberClass} 'any(.[]; .class == $class)' >/dev/null
      }

      if ! roblox_running; then
        notify "Roblox isn't running" "Open Roblox first, then turn anti-AFK on."
        exit 0
      fi

      notify "Roblox anti-AFK on" \
        "Pressing ${antiAfkKey} every ${toString antiAfkInterval}s while Roblox is focused. Super+Alt+A turns it off."
      reason="Turned off."
      # systemctl stop sends SIGTERM; exiting through it runs the EXIT trap.
      trap 'exit 0' TERM INT
      trap 'notify "Roblox anti-AFK off" "$reason"' EXIT

      while true; do
        if ! roblox_running; then
          reason="Roblox was closed."
          exit 0
        fi

        active=$(hyprctl activewindow -j | jq -r '.class // ""')
        locked=$(caelestia shell lock isLocked 2>/dev/null || echo false)
        if [ "$active" = ${soberClass} ] && [ "$locked" != true ]; then
          # Each CLI call gets a fresh virtual keyboard; the delay gives
          # Hyprland time to pick it up before the key goes out. Held
          # briefly rather than tapped, so Roblox can't miss it.
          if ! out=$(crossmacro run \
            --step "delay 500" \
            --step "key down ${antiAfkKey}" \
            --step "delay 100" \
            --step "key up ${antiAfkKey}" 2>&1); then
            reason="CrossMacro couldn't send input: $(tail -n 3 <<<"$out")"
            exit 1
          fi
        fi

        sleep ${toString antiAfkInterval}
      done
    '';
  };

  # Starts or stops the loop. Bound to Super+Alt+A, and in the app
  # launcher as "Roblox Anti-AFK".
  antiAfkToggle = pkgs.writeShellScriptBin "roblox-anti-afk" ''
    if systemctl --user is-active --quiet roblox-anti-afk.service; then
      exec systemctl --user stop roblox-anti-afk.service
    else
      exec systemctl --user start roblox-anti-afk.service
    fi
  '';

  antiAfkDesktopItem = pkgs.makeDesktopItem {
    name = "roblox-anti-afk";
    desktopName = "Roblox Anti-AFK";
    comment = "Toggle pressing ${antiAfkKey} every ${toString antiAfkInterval}s while Roblox is focused";
    exec = "${antiAfkToggle}/bin/roblox-anti-afk";
    icon = soberClass;
    categories = [ "Game" ];
  };
in
{
  # The app (in the launcher as "CrossMacro"), its daemon, uinput, udev and
  # polkit rules, and the `crossmacro` group for these users.
  services.crossmacro = {
    enable = true;
    users = [ username ];
  };

  home-manager.users.${username} = {
    home.packages = [
      antiAfkToggle       # `roblox-anti-afk`: turn anti-AFK on/off
      antiAfkDesktopItem  # its "Roblox Anti-AFK" launcher entry
    ];

    # Started and stopped only by the toggle, never at login. It runs from
    # the user manager, whose environment Hyprland fills in (hyprctl and
    # CrossMacro both need HYPRLAND_INSTANCE_SIGNATURE/WAYLAND_DISPLAY).
    systemd.user.services.roblox-anti-afk = {
      Unit.Description = "Roblox anti-AFK: press a key periodically while Roblox is focused";
      Service.ExecStart = "${antiAfkLoop}/bin/roblox-anti-afk-loop";
    };

    # Appended to home/hyprland.nix's hypr-user.lua (`text` merges as lines).
    xdg.configFile."caelestia/hypr-user.lua".text = lib.mkAfter ''

      -- Roblox anti-AFK on/off (gaming/crossmacro.nix).
      hl.bind("SUPER + ALT + A", hl.dsp.exec_cmd("${antiAfkToggle}/bin/roblox-anti-afk"))
    '';
  };
}
