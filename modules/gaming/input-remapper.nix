{ config, pkgs, username, ... }:

# Input Remapper: a GUI for changing what each key or button of one
# specific input device does. Here that's mainly the Razer Tartarus Pro
# keypad. A key can become another key, a combination (e.g. Ctrl+C), a
# mouse click or scroll, or a macro. Mappings are made in the app (in the
# launcher as "Input Remapper") and saved as presets in
# ~/.config/input-remapper-2. The ones kept in this repo are copied there
# when missing (Presets, below). See docs/gaming.md.
#
# Like CrossMacro (crossmacro.nix), it works on Wayland through a root
# daemon (input-remapper.service). The daemon grabs the device and sends its
# input back out through a virtual uinput device with the mappings applied.
# Unmapped keys pass through unchanged, and everything still goes through
# the normal keyboard layout.
let
  package = config.services.input-remapper.package;

  # --- Presets ---
  # The presets kept in this repo. The folder mirrors the app's own presets
  # folder (<device name>/<preset name>.json), so a preset made or changed in
  # the app is kept by copying its file back here. Each one is copied into
  # place on activation only if it isn't there yet: seeded, not managed,
  # since the app saves over its presets in place and can't write to a
  # read-only store symlink. So a change made here only reaches a machine
  # that doesn't have that preset yet, or once its copy there is deleted.
  #
  # Mappings name the event device each key comes from by a hash of its name
  # and capabilities. The Tartarus is two keyboard devices (keys 01-20 on
  # one, the round button and D-pad on the other), and when a hash doesn't
  # match, the daemon falls back to any device that can send the key, which
  # can be the wrong half. The hashes only change if a kernel update changes
  # what the keypad reports; docs/gaming.md has the fix.
  presets = ./input-remapper-presets;

  # The preset each device loads at login and when plugged in. Only added
  # for devices that don't have one yet, so a choice made in the app wins.
  autoload = {
    "Razer Razer Tartarus Pro" = "Layout";
  };

  # A first config.json. Without one, the app takes its presets for
  # version 0.0.0 ones and runs every old-format migration over them, which
  # rewrites these. Stating the installed version skips that.
  initialConfig = pkgs.writeText "input-remapper-config.json"
    (builtins.toJSON { version = package.version; autoload = { }; });
in
{
  # The app, its daemon, D-Bus and polkit policy.
  services.input-remapper.enable = true;

  home-manager.users.${username} = { config, lib, ... }: {
    # --- Loading presets at login ---
    # Presets marked "Autoload" in the app are applied by
    # `input-remapper-control --command autoload`, and it has to run as the
    # user: that's how the daemon learns whose config to read. Other desktops
    # run it from an XDG autostart entry, but nothing runs those here (greetd
    # execs Hyprland directly, desktop/session.nix), so it's a user service
    # instead. At login the daemon may still be starting, and the command
    # fails (exit 5) until it answers, hence the retries.
    systemd.user.services.input-remapper-autoload = {
      Unit = {
        Description = "Load input-remapper's autoload presets";
        # Up to 10 tries, then give up instead of retrying forever.
        StartLimitIntervalSec = 60;
        StartLimitBurst = 10;
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${package}/bin/input-remapper-control --command autoload";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Seeds the presets and autoload entries in the let block (see Presets).
    # Activation runs at boot, before login, so they're in place when the
    # service above applies them. config.json is only rewritten when an
    # autoload entry is actually missing.
    home.activation.seedInputRemapperPresets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      dir="${config.xdg.configHome}/input-remapper-2"
      $DRY_RUN_CMD mkdir -p "$dir/presets"
      $DRY_RUN_CMD cp -r --update=none --no-preserve=mode ${presets}/. "$dir/presets/"

      cfg="$dir/config.json"
      [ -s "$cfg" ] || $DRY_RUN_CMD cp --no-preserve=mode ${initialConfig} "$cfg"
      # --indent 4: the app's own formatting, so an unchanged file compares equal.
      ${pkgs.jq}/bin/jq --indent 4 --argjson autoload ${lib.escapeShellArg (builtins.toJSON autoload)} \
        '.autoload = $autoload + (.autoload // {})' "$cfg" > "$cfg.tmp"
      if ${pkgs.diffutils}/bin/cmp -s "$cfg.tmp" "$cfg"; then
        rm "$cfg.tmp"
      else
        $DRY_RUN_CMD mv "$cfg.tmp" "$cfg"
      fi
    '';
  };

  # --- Hotplug ---
  # Re-applies a device's preset when it's plugged back in; otherwise a
  # replugged keypad would stay unmapped until the next login. The daemon
  # already knows the user's config by then (from the login service above),
  # so this can run as root from udev.
  #
  # Not upstream's own rule (services.input-remapper.enableUdevRules):
  # that one fires for every new input device, virtual ones too. udev holds
  # a new device back from Hyprland until its RUN commands finish, and this
  # one takes ~0.3-0.5s. CrossMacro creates a fresh virtual keyboard for
  # every `crossmacro run` and waits only 500ms for Hyprland to pick it up
  # (the Roblox anti-AFK loop), so the delay could make those key presses
  # go nowhere. This version skips virtual (uinput) devices. That also
  # covers input-remapper's own output devices, which upstream skips too.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", DEVPATH!="/devices/virtual/*", ENV{ID_PATH}!="platform-sound", RUN+="${package}/bin/input-remapper-control --command autoload --device $env{DEVNAME}"
  '';

  # The rest of upstream's udev rules, which is safe to take as-is: it tags
  # input-remapper's output devices as USB, so a remapped mouse keeps its
  # hwdb properties (DPI) and its pointer doesn't feel different.
  services.udev.packages = [
    (pkgs.runCommand "input-remapper-forwarded-udev-rules" { } ''
      install -Dm644 -t $out/lib/udev/rules.d \
        ${package}/etc/udev/rules.d/69-input-remapper-forwarded.rules
    '')
  ];
}
