{ ... }:

# Hardware support that isn't auto-detected: Bluetooth and firmware
# updates. GPUs are in gpu.nix; the auto-generated half (kernel modules,
# microcode) is each machine's hosts/<name>/hardware-configuration.nix.
{
  # --- Bluetooth ---
  hardware.bluetooth.enable = true;
  services.blueman.enable = true; # pairing/management GUI + tray applet

  # --- Firmware updates ---
  # fwupd checks the LVFS for BIOS/UEFI, SSD and peripheral firmware.
  # Nothing runs automatically — check and apply by hand:
  #   fwupdmgr refresh && fwupdmgr update
  services.fwupd.enable = true;
}
