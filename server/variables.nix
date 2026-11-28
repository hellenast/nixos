{
  # The server's settings (docs/beeper-bridges.md). Separate from
  # variables.nix and hosts/: the server shares none of the desktop/laptop
  # modules.

  hostname = "hyena-cloud";

  # SSH public keys allowed to log in as root — deploys run over SSH from
  # the desktop. The contents of ~/.ssh/id_ed25519.pub.
  sshAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGeUQOthXZXxpWrYU3YEvR/iqO2MZeP3RT3IymS8XZj2 hyena@hyena"
  ];

  # The disk nixos-anywhere installs on (server/disko.nix). Oracle's A1 VMs
  # show their boot volume as /dev/sda; `lsblk` on the VM before installing
  # confirms it.
  disk = "/dev/sda";
}
