{ config, pkgs, username, ... }:

# Input Remapper: a GUI for changing what each key or button of one
# specific input device does. Here that's mainly the Razer Tartarus Pro
# keypad. A key can become another key, a combination (e.g. Ctrl+C), a
# mouse click or scroll, or a macro. Mappings are made in the app (in the
# launcher as "Input Remapper") and saved as presets in
# ~/.config/input-remapper-2, not managed by Nix. See docs/gaming.md.
#
# Like CrossMacro (crossmacro.nix), it works on Wayland through a root
# daemon (input-remapper.service). The daemon grabs the device and sends its
# input back out through a virtual uinput device with the mappings applied.
# Unmapped keys pass through unchanged, and everything still goes through
# the normal keyboard layout.
let
  package = config.services.input-remapper.package;
in
{
  # The app, its daemon, D-Bus and polkit policy.
  services.input-remapper.enable = true;

  # --- Loading presets at login ---
  # Presets marked "Autoload" in the app are applied by
  # `input-remapper-control --command autoload`, and it has to run as the
  # user: that's how the daemon learns whose config to read. Other desktops
  # run it from an XDG autostart entry, but nothing runs those here (greetd
  # execs Hyprland directly, desktop/session.nix), so it's a user service
  # instead. At login the daemon may still be starting, and the command
  # fails (exit 5) until it answers, hence the retries.
  home-manager.users.${username}.systemd.user.services.input-remapper-autoload = {
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
