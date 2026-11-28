{ lib, buildGoModule, fetchFromGitHub }:

# Beeper Bridge Manager: registers self-hosted bridges with a Beeper account
# and runs them (../bridges.nix). Not in nixpkgs.
buildGoModule (finalAttrs: {
  pname = "bbctl";
  version = "0.15.0";

  src = fetchFromGitHub {
    owner = "beeper";
    repo = "bridge-manager";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3vfZmnjPAdTNejlNE0m2Kd63ZRCtsZgTpz5YEBVkC3I=";
  };

  vendorHash = "sha256-X4DbDfiu1VAhFAUT+VH5T4GpeofjhLDdoKwyNVBA9A4=";
  subPackages = [ "cmd/bbctl" ];
  ldflags = [ "-s" "-w" "-X" "main.Tag=v${finalAttrs.version}" ];

  meta = {
    description = "Tool for running self-hosted bridges with the Beeper Matrix server";
    homepage = "https://github.com/beeper/bridge-manager";
    license = lib.licenses.asl20;
    mainProgram = "bbctl";
  };
})
