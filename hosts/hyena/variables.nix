# hyena: the desktop. AMD CPU, AMD graphics (a Radeon RX 9060 XT, plus the
# CPU's own), two monitors, US keyboard.
#
# Every machine in hosts/ sets all of these; docs/machines.md explains each
# one. The hostname is this folder's name.
{
  # --- Hardware ---
  # Laptop features: battery, brightness, lid, suspend.
  isLaptop = false;
  # "amd" or "intel".
  cpu = "amd";
  # Every GPU vendor in the machine: "amd", "intel" and/or "nvidia".
  gpus = [ "amd" ];
  # PCI addresses for NVIDIA PRIME; only machines with NVIDIA next to
  # another GPU need them.
  gpuBusIds = { };
  # The disk fresh-install.sh installs on (modules/system/disko.nix): the
  # Kingston NVMe.
  disk = "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7686E83FA7";

  # --- Keyboard ---
  # TTY keymap (`localectl list-keymaps`): plain virtual consoles only.
  consoleKeyMap = "us-acentos";
  # Hyprland's XKB layout, variant and model (`localectl
  # list-x11-keymap-variants <layout>`). "intl" adds dead-key composition
  # (e.g. ' + c -> ç); "" for a plain layout or the default model.
  keyboardLayout = "us";
  keyboardVariant = "intl";
  keyboardModel = "";

  # --- Monitors ---
  # Hyprland outputs (`hyprctl monitors`), in order: primary on the left at
  # its full refresh rate, secondary to its right. Also takes `scale`
  # (default 1, or "auto") and `transform` (0 = normal, 1 = 90°, 2 = 180°,
  # 3 = 270°).
  monitors = [
    { output = "DP-2"; mode = "2560x1440@165"; position = "0x0"; }
    # Physically mounted rotated.
    { output = "HDMI-A-1"; mode = "2560x1080@60"; position = "2560x0"; transform = 3; }
  ];

  # --- Modules ---
  # Files in modules/ this machine leaves out, e.g. "gaming/vr.nix" or
  # "home/apps/spotify.nix". fresh-install.sh's module picker writes this.
  disabledModules = [ ];
}
