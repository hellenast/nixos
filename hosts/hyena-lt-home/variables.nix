# hyena-lt-home: the home laptop. Intel CPU and its integrated graphics,
# ABNT2 keyboard.
#
# Every machine in hosts/ sets all of these; docs/machines.md explains each
# one. The hostname is this folder's name.
{
  # --- Hardware ---
  # Laptop features: battery, brightness, lid, suspend.
  isLaptop = true;
  # "amd" or "intel".
  cpu = "intel";
  # Every GPU vendor in the machine: "amd", "intel" and/or "nvidia".
  gpus = [ "intel" ];
  # PCI addresses for NVIDIA PRIME; only machines with NVIDIA next to
  # another GPU need them.
  gpuBusIds = { };
  # The disk fresh-install.sh installs on (modules/system/disko.nix). It
  # sets this to the disk picked during the install.
  disk = "/dev/disk/by-id/set-by-fresh-install";

  # --- Keyboard ---
  # TTY keymap (`localectl list-keymaps`): plain virtual consoles, and the
  # LUKS passphrase prompt (system/base.nix).
  consoleKeyMap = "br-abnt2";
  # Hyprland's XKB layout, variant and model. "br" is ABNT2 by default,
  # dead keys included; the abnt2 model gets the keypad's comma right.
  keyboardLayout = "br";
  keyboardVariant = "";
  keyboardModel = "abnt2";

  # --- Monitors ---
  # The built-in screen, at its native mode, scaled for its size by
  # Hyprland. External monitors are laid out automatically; list them here
  # (like hosts/hyena does) to pin their mode and position.
  monitors = [
    { output = "eDP-1"; mode = "preferred"; position = "0x0"; scale = "auto"; }
  ];

  # --- Modules ---
  # Files in modules/ this machine leaves out. fresh-install.sh's module
  # picker writes this.
  disabledModules = [
    "virtualisation/windows-vm.nix"     # built around the desktop's USB mic, and starts at boot
    "virtualisation/audio-routing.nix"  # the Windows VM's virtual mic
    "gaming/vr.nix"                     # ALVR needs a GPU that can render VR
  ];
}
