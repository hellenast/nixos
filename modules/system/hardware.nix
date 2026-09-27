{ ... }:

# Hardware support that isn't auto-detected: GPU, Bluetooth, firmware
# updates. The auto-generated half (kernel modules, microcode) is
# hardware-configuration.nix.
{
  # --- AMD GPU ---
  # enable32Bit is for 32-bit games under Steam/Proton, and Wine (Bottles).
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # amdgpu already loads on its own, but only once stage 2 gets to it.
  # Until then, Plymouth's splash and the LUKS prompt (boot.nix) run on the
  # firmware's EFI framebuffer at the wrong, non-native resolution. Loading
  # it in the initrd gives Plymouth real KMS from the first frame.
  boot.initrd.kernelModules = [ "amdgpu" ];

  # --- Bluetooth ---
  hardware.bluetooth.enable = true;
  services.blueman.enable = true; # pairing/management GUI + tray applet

  # --- Firmware updates ---
  # fwupd checks the LVFS for BIOS/UEFI, SSD and peripheral firmware.
  # Nothing runs automatically — check and apply by hand:
  #   fwupdmgr refresh && fwupdmgr update
  services.fwupd.enable = true;
}
