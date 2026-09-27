{ ... }:

# Nix itself: flakes, unfree packages, store cleanup, and running
# non-Nix binaries.
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Every system and home-manager generation keeps its whole closure in the
  # store until something collects it, and frequent flake updates pile them
  # up fast. A daily sweep keeps a week of generations — enough to roll back
  # a bad rebuild from a few days ago.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # Lets prebuilt, dynamically linked binaries (downloaded tools, npm
  # packages with native bits, ...) find a loader and common libraries
  # instead of failing with "No such file or directory".
  programs.nix-ld.enable = true;
}
