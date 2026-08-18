{ config, pkgs, ... }:

{
  # fwupd: checks the LVFS (Linux Vendor Firmware Service) for firmware
  # updates — BIOS/UEFI, SSDs, peripherals that support it — and applies
  # them via `fwupdmgr` (CLI) or GNOME Firmware (GUI, not installed here,
  # fwupdmgr covers it). Nothing here runs automatically: `fwupdmgr
  # refresh` checks for updates, `fwupdmgr update` applies them, both need
  # to be run by hand.
  services.fwupd.enable = true;
}
