{ ... }:

# This machine never sleeps on its own.
{
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
}
