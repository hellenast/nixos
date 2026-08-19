{ config, pkgs, ... }:

{
  # fwupd: checks the LVFS (Linux Vendor Firmware Service) for firmware
  # updates — BIOS/UEFI, SSDs, peripherals that support it — and applies
  # them via `fwupdmgr` (CLI) or GNOME Firmware (GUI, not installed here,
  # fwupdmgr covers what I need). Nothing here runs automatically: I run
  # `fwupdmgr refresh` to check for updates and `fwupdmgr update` to apply
  # them, both by hand.
  services.fwupd.enable = true;
}
