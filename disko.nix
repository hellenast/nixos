# My declarative disk layout for a from-scratch install, applied with disko
# from the NixOS live ISO (see README.md -> "Reinstalling with full-disk
# encryption") instead of partitioning/formatting/mounting by hand. Once
# applied, this module also supplies `fileSystems`, `swapDevices`, and
# `boot.initrd.luks.devices` to every regular `nixos-rebuild switch` — that's
# why hardware-configuration.nix no longer defines those itself.
#
# Layout: an unencrypted 512M EFI System Partition (systemd-boot needs to
# read it before any decryption happens), then a single LUKS2 partition
# filling the rest of the disk, containing a btrfs volume with the same
# subvolumes my machine already had (root/home/nix/log/persist) plus a
# btrfs-native swapfile subvolume — so root, home, nix, logs, persisted
# state, and swap all sit behind one passphrase prompt at boot. Only /boot
# stays plaintext, which is normal: it holds the kernel/initrd, not user
# data, and systemd-boot itself can't read an encrypted ESP anyway.
#
# I address the disk by its stable /dev/disk/by-id path (not /dev/nvme0n1)
# so this doesn't silently target the wrong drive if device enumeration ever
# shifts. Re-check `ls /dev/disk/by-id/` on the actual install target before
# running disko — this id is specific to my machine's Kingston NVMe drive.
{
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
                # No passwordFile/keyFile set on purpose: disko prompts me
                # for the passphrase interactively while partitioning, and
                # with no keyFile carried into the resulting config, every
                # future boot prompts for it too via systemd-boot's initrd
                # — that's the actual encryption, not just an install-time
                # step.
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
