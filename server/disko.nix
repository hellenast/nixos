{ ... }:

let
  vars = import ./variables.nix;
in
# The server's disk: an EFI partition and one ext4 root. No encryption,
# unlike the desktop's (system/disko.nix): nobody is there to type a
# passphrase when the VM boots. nixos-anywhere applies it once, during
# install; afterwards it only supplies the fileSystems config.
{
  disko.devices.disk.main = {
    type = "disk";
    device = vars.disk;
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
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
