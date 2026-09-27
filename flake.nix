{
  description = "NixOS + Hyprland + Caelestia shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Flatpak management, used twice: system-wide
    # (modules/desktop/flatpak.nix) for most apps, and user-scope for
    # Spotify (modules/home/apps/spotify.nix), which has to be writable for
    # spicetify to patch it.
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # The desktop shell (bar, launcher, lock screen, dynamic theming...) and
    # the CLI that drives it. caelestia-cli isn't referenced directly:
    # caelestia-shell follows it, so the CLI version is pinned here.
    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-cli = {
      url = "github:caelestia-dots/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Not a flake, just the caelestia dotfiles repo (Hyprland config, fish,
    # spicetify theme, Thunar/VSCodium/Zen config, ...). The modules use
    # pieces of it directly, some patched.
    caelestia-dots-src = {
      url = "github:caelestia-dots/caelestia";
      flake = false;
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helium-browser = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declares the Windows VM (modules/virtualisation/windows-vm.nix) in
    # libvirt, instead of setting it up in virt-manager by hand.
    nixvirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Decrypts secrets/secrets.yaml at activation
    # (modules/system/secrets.nix), so secrets like the ProtonVPN WireGuard
    # config can live in this repo, encrypted.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning (modules/system/disko.nix): a
    # from-scratch install is one command from the live ISO instead of
    # cryptsetup/mkfs/mount by hand. Only partitions during a reinstall; on
    # normal rebuilds it just supplies the filesystem config.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Runs the real Windows (GDK) build of Minecraft Bedrock Edition under
    # steam-run/Proton, with native Xbox sign-in
    # (modules/gaming/minecraft.nix). docs/gaming.md explains why this and
    # not mcpelauncher or Waydroid.
    bedrock-on-linux = {
      url = "github:Wyze3306/BedrockOnLinux";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Millennium, the Steam client modding framework the caelestia Steam
    # theme runs under (modules/gaming/steam.nix). Pinned in the URL, not
    # just in flake.lock, because the deploy command doesn't copy flake.lock
    # into /etc/nixos (docs/deploying.md), so it would otherwise lock
    # whatever main is at deploy time. The rev is the commit that packages
    # release v3.5.0: upstream updates packages/nix in a follow-up commit
    # after each release, so the release tag still has the previous
    # version's packaging. No nixpkgs `follows` on purpose: its build
    # fetches Bun dependencies as a fixed-output derivation whose hash only
    # matches the Bun in its own pinned nixpkgs.
    millennium.url = "github:SteamClientHomebrew/Millennium/1e65b76114450a505905432bfeae0cf87b6d286e?dir=packages/nix";
  };

  outputs = { nixpkgs, home-manager, ... } @ inputs: let
    system = "x86_64-linux";

    # Everything specific to this machine and user (username, hostname,
    # locale, monitors, cursor, ...) — see variables.nix. Passed to every
    # module as plain arguments via specialArgs, so adapting the repo to
    # another machine is a one-file edit.
    vars = import ./variables.nix;
    inherit (vars) username hostname;
  in {
    nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; } // vars;
      modules = [
        # All system modules (see modules/default.nix). Modules that need
        # another flake's NixOS module (sops-nix, disko, NixVirt,
        # nix-flatpak) import it themselves.
        ./modules

        # The user's home-manager config (modules/home).
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.extraSpecialArgs = { inherit inputs; } // vars;
          home-manager.users.${username} = import ./modules/home;
        }
      ];
    };
  };
}
