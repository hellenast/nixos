# Declarative disk layout, applied once with disko from the NixOS live ISO
# during a from-scratch install (docs/installing.md) instead of
# partitioning/formatting by hand. On every normal rebuild, this module also
# supplies `fileSystems`, `swapDevices` and `boot.initrd.luks.devices` —
# which is why hardware-configuration.nix doesn't.
#
# Layout: a plaintext 512M EFI System Partition (systemd-boot has to read it
# before anything is decrypted; it only holds the kernel/initrd), then one
# LUKS2 partition filling the rest of the disk. Inside it is a btrfs volume
# with root/home/nix/log/persist subvolumes and a swapfile subvolume, so
# everything except /boot sits behind one passphrase at boot.
#
# The disk is addressed by its stable /dev/disk/by-id path, not
# /dev/nvme0n1, so a change in device enumeration can't point this at the
# wrong drive. The id is this machine's Kingston NVMe — check
# `ls /dev/disk/by-id/` on the install target first (fresh-install.sh does).
{ inputs, ... }:

{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7686E83FA7";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "fmask=0022" "dmask=0022" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                # No passwordFile/keyFile on purpose: disko asks for the
                # passphrase while partitioning, and with no key file in the
                # config, the initrd asks for it on every boot too.
                settings = {
                  allowDiscards = true; # SSD: let TRIM reach the underlying device
                };
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                    };
                    "/home" = {
                      mountpoint = "/home";
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                    };
                    "/log" = {
                      mountpoint = "/var/log";
                    };
                    "/persist" = {
                      mountpoint = "/persist";
                    };
                    "/swap" = {
                      mountpoint = "/.swapvol";
                      swap.swapfile.size = "8G"; # matches the old dedicated swap partition
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
