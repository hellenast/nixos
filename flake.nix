{
  description = "NixOS + Hyprland + Caelestia shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Flatpak management, used twice: system-wide in
    # configuration.nix for most apps, and user-scope in home.nix
    # specifically for Spotify (needs to be writable so spicetify can
    # patch it, which a root-owned system install isn't).
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # The actual desktop shell (bar, launcher, lock screen, dynamic
    # theming...) and the CLI that drives it.
    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-cli = {
      url = "github:caelestia-dots/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Not a flake itself, just the dotfiles repo (Hyprland config, fish,
    # spicetify theme, Thunar/VSCodium integration, ...) that I vendor
    # pieces of directly in home.nix.
    caelestia-dots-src = {
      url = "github:caelestia-dots/caelestia";
      flake = false;
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Manages the Windows VM (see windows-vm.nix) declaratively through
    # libvirt, instead of me clicking through virt-manager by hand.
    nixvirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Decrypts secrets (see secrets.nix) at activation time so things like
    # the ProtonVPN WireGuard config can live in this repo encrypted,
    # instead of as a plain root-only file I have to remember to place by
    # hand outside of Nix entirely.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, caelestia-shell, caelestia-cli, caelestia-dots-src, zen-browser, ... } @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };

    # Single source of truth for my login user name, threaded into every
    # module below as a specialArg so it's a one-line change everywhere it's
    # used (users.users, home.username, sudo rules, /home paths, ...).
    username = "hyena";
    # Kept right next to username as a reminder to update both together —
    # this is the human-readable form of the same account (users.users.*.description).
    userDescription = "Hyena";
    # Kept right next to username/userDescription too: the machine's own
    # name (networking.hostName), a different concept from the login user
    # but easy to forget when it happens to match. Also drives the
    # `nixosConfigurations.<name>` attribute below, since
    # `nixos-rebuild switch --flake .#` (no name after `#`) picks the config
    # whose attribute name matches the actual machine hostname.
    hostname = "hyena";
  in {
    nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs username userDescription hostname; };
      modules = [
        ./configuration.nix
        ./windows-vm.nix
        ./audio-routing.nix
        ./vr.nix
        ./gaming.nix
        ./caelestia-system.nix
        ./amazfit.nix
        ./media.nix
        ./dev.nix
        ./protonvpn.nix
        ./tor.nix
        ./secrets.nix
        ./firmware.nix
        ./oom.nix

        inputs.nix-flatpak.nixosModules.nix-flatpak
        inputs.nixvirt.nixosModules.default
        inputs.sops-nix.nixosModules.sops

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.extraSpecialArgs = { inherit inputs username; };
          home-manager.users.${username} = import ./home.nix;
        }
      ];
    };
  };
}
