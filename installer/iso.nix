{ lib, pkgs, modulesPath, inputs, ... }:

# The install stick's ISO, which prepare-usb.sh builds and writes: NixOS's
# minimal installer, plus a `fresh-install` command, so installing is
# booting the stick and running `sudo fresh-install` — no partition to mount
# by hand. The command runs the fresh-install.sh on the stick's NIXCFG
# partition (see fresh-install-launcher.sh), so the repo there can be
# refreshed without building a new ISO. Nothing machine-specific is baked
# in: the repo and the age key stay on NIXCFG.
let
  # disko as fresh-install.sh runs it (`nix run .#disko`, built from this
  # flake's nixpkgs, the same as this ISO's), plus everything its
  # partitioning script uses: the layout's own list (disko reports it —
  # including a cryptsetup wrapper it builds), and what wiping the old disk
  # takes. With all of it on the ISO, the partitioning step downloads and
  # builds nothing: into a live ISO's RAM-backed store, disko's download
  # (hundreds of MiB, plus a compiler) is what ran out of space.
  anyMachine = builtins.head (builtins.attrValues inputs.self.nixosConfigurations);
  diskoTools = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.disko ]
    ++ anyMachine.config.disko.devices._packages pkgs
    ++ (with pkgs; [ util-linux e2fsprogs mdadm lvm2 bash jq gnused gawk coreutils-full ])
    # What building the script itself takes: it's a plain text file, but
    # nixpkgs' script writer lists a binary-wrapper hook as a build tool,
    # and that brings a C compiler along. On the stick, it costs RAM nothing.
    ++ [ pkgs.stdenvNoCC ] ++ anyMachine.config.system.build.destroyFormatMount.nativeBuildInputs;

  freshInstall = pkgs.writeShellApplication {
    name = "fresh-install";
    runtimeInputs = with pkgs; [ util-linux findutils coreutils ];
    # The repo's fresh-install.sh as it was when the ISO was built, for a
    # stick without NIXCFG.
    text = builtins.replaceStrings [ "@builtin@" ] [ "${../fresh-install.sh}" ]
      (builtins.readFile ./fresh-install-launcher.sh);
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  # Only the file's name; the volume label the ISO finds itself by at boot
  # stays the stock one.
  image.baseName = lib.mkForce "nixos-hyena-installer-${pkgs.stdenv.hostPlatform.system}";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # The live system keeps everything in RAM and has no swap, while
  # evaluating the configuration takes about 2 GB more: on a laptop with
  # little RAM that crawls for hours instead of failing. Compressed swap in
  # RAM gives it room (fresh-install.sh adds the same on stock ISOs).
  zramSwap.enable = true;

  environment.systemPackages = [
    freshInstall
    pkgs.age   # age-keygen, to check the age key without downloading it
    pkgs.rsync # copying the repo around
  ];

  # On the ISO, not installed: as installed packages, the disko wrapper's
  # bin/cryptsetup lost to the ISO's own cryptsetup when the system's
  # packages were merged, nothing referenced the wrapper anymore, and it
  # was left out of the image — so disko built it again, with a compiler.
  system.extraDependencies = diskoTools;

  services.getty.helpLine = lib.mkAfter ''

    To install one of the machines in the repo on the NIXCFG partition:
      sudo fresh-install
  '';
}
