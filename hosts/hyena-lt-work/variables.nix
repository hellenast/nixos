# hyena-lt-work: the work laptop. AMD CPU, whose integrated graphics run
# the desktop, plus an NVIDIA GPU for what's offloaded to it (PRIME). ABNT2
# keyboard.
#
# Every machine in hosts/ sets all of these; docs/machines.md explains each
# one. The hostname is this folder's name.
{
  # --- Hardware ---
  # Laptop features: battery, brightness, lid, suspend.
  isLaptop = true;
  # "amd" or "intel".
  cpu = "amd";
  # Every GPU vendor in the machine: "amd", "intel" and/or "nvidia".
  gpus = [ "amd" "nvidia" ];
  # PCI addresses for NVIDIA PRIME, as "PCI:bus:device:function" in decimal
  # (`lspci` shows them in hex). fresh-install.sh detects and sets them;
  # these are typical values, not this laptop's.
  gpuBusIds = { amd = "PCI:6:0:0"; nvidia = "PCI:1:0:0"; };
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
  ];
}
