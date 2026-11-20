{ ... }:

# Hardware support that isn't auto-detected: Bluetooth and firmware
# updates. GPUs are in gpu.nix; the auto-generated half (kernel modules,
# microcode) is each machine's hosts/<name>/hardware-configuration.nix.
let
  # See the MediaTek note under Bluetooth below.
  blockMediatekBluetooth = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="13d3", ATTR{idProduct}=="3596", ATTR{authorized}="0"
  '';
in
{
  # --- Bluetooth ---
  hardware.bluetooth.enable = true;
  services.blueman.enable = true; # pairing/management GUI + tray applet

  # The desktop's ASUS board has an onboard MediaTek MT7902 Wi-Fi/Bluetooth
  # chip that Linux can't drive: its Wi-Fi has no driver, and btusb binds
  # its Bluetooth (USB 13d3:3596) but the controller never answers, so
  # every boot printed "Bluetooth: hci0: Opcode 0x0c03 failed: -110" on
  # the console. The Intel AX210 card does Wi-Fi and Bluetooth instead.
  # Deauthorizing the USB device keeps every driver off it. Matches only
  # that exact chip, so it's a no-op on machines without it; turning the
  # onboard wireless off in the BIOS would do the same.
  #
  # Applied in the initrd too, where the chip already shows up (~2s into
  # boot) while btusb doesn't exist yet. With the rule only in the booted
  # system it raced btusb: loading btusb (for the Intel card, ~14s) binds
  # it to every matching device on the spot, before udev gets to this rule,
  # so on some boots the doomed reset was already queued and the error
  # still printed. Deauthorized in the initrd, the chip stays that way
  # after the switch to the real root.
  services.udev.extraRules = blockMediatekBluetooth;
  boot.initrd.services.udev.rules = blockMediatekBluetooth;

  # --- Firmware updates ---
  # fwupd checks the LVFS for BIOS/UEFI, SSD and peripheral firmware.
  # Nothing runs automatically — check and apply by hand:
  #   fwupdmgr refresh && fwupdmgr update
  services.fwupd.enable = true;
}
