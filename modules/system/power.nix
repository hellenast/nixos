{ lib, isLaptop, cpu, ... }:

# How the machine sleeps and handles power, from isLaptop in its
# hosts/<name>/variables.nix: the desktop never sleeps on its own; laptops
# suspend, and get battery and power-profile support for the shell.
{
  config = lib.mkMerge [
    (lib.mkIf (!isLaptop) {
      # Disabling the sleep targets outright blocks every path into them — a
      # stray `systemctl suspend`, the power button, the lid switch — not just
      # the idle timeout. (Idle/lock is handled by caelestia-shell, not
      # hypridle — see home/hyprland.nix.)
      systemd.targets.sleep.enable = false;
      systemd.targets.suspend.enable = false;
      systemd.targets.hibernate.enable = false;
      systemd.targets.hybrid-sleep.enable = false;

      # logind reacts to the lid switch by itself, separately from the targets
      # above, so it needs telling too.
      services.logind.settings.Login = {
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
      };
    })

    (lib.mkIf isLaptop {
      # Closing the lid suspends, unless an external monitor is connected
      # (what logind calls docked). caelestia-shell also suspends after 10
      # idle minutes, and locks before any suspend.
      services.logind.settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "suspend";
        HandleLidSwitchDocked = "ignore";
      };

      # No hibernation: resuming would need the swapfile's offset inside the
      # encrypted btrfs volume (disko.nix), which isn't set up. Disabled
      # outright so nothing tries; the shell's "suspend then hibernate"
      # sees that and suspends instead (and so does the dots' sleep bind,
      # through home/hyprland.nix).
      systemd.targets.hibernate.enable = false;
      systemd.targets.hybrid-sleep.enable = false;
      systemd.targets.suspend-then-hibernate.enable = false;

      # Battery level and charging state, for the shell's bar icon and
      # low-battery warnings.
      services.upower.enable = true;
      # Power saver / balanced / performance profiles, switchable from the
      # shell's dashboard.
      services.power-profiles-daemon.enable = true;
      # Intel's thermal daemon keeps the CPU from overheating or throttling
      # hard under sustained load. Intel CPUs only.
      services.thermald.enable = cpu == "intel";
    })
  ];
}
