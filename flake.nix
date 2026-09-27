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
    lib = nixpkgs.lib;

    # One configuration per folder in hosts/, named after it. The folder
    # name is also the machine's hostname, so `nixos-rebuild switch --flake
    # .#` (no name after `#`) picks the right one by itself.
    hostnames = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts));

    mkHost = hostname: let
      # variables.nix (shared: user, locale, cursor) overlaid with the
      # machine's own hosts/<name>/variables.nix (hardware, keyboard,
      # monitors, modules left out). Passed to every module as plain
      # arguments via specialArgs — see docs/machines.md.
      vars = import ./variables.nix // import ./hosts/${hostname}/variables.nix // { inherit hostname; };
      args = { inherit inputs; } // removeAttrs vars [ "disabledModules" ];

      # The machine's disabledModules as paths: the files under modules/
      # it leaves out, the home/ ones from home-manager's module list.
      disabled = home: map (module: ./modules + "/${module}")
        (builtins.filter (module: lib.hasPrefix "home/" module == home) vars.disabledModules);
    in lib.nixosSystem {
      inherit system;
      specialArgs = args;
      modules = [
        # All system modules (see modules/default.nix), minus the ones this
        # machine leaves out. Modules that need another flake's NixOS
        # module (sops-nix, disko, NixVirt, nix-flatpak) import it
        # themselves.
        ./modules
        { disabledModules = disabled false; }
        ./hosts/${hostname}/hardware-configuration.nix

        # The user's home-manager config (modules/home), minus the ones this
        # machine leaves out. Two separate definitions, so modules/home stays
        # a top-level module of the user's config rather than an import of
        # one: that keeps the order its packages are merged in.
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.extraSpecialArgs = args;
          home-manager.users.${vars.username} = import ./modules/home;
        }
        { home-manager.users.${vars.username}.disabledModules = disabled true; }
      ];
    };
  in {
    nixosConfigurations = lib.genAttrs hostnames mkHost;

    # The install stick's ISO: NixOS's minimal installer plus a
    # `fresh-install` command (installer/iso.nix). prepare-usb.sh builds it
    # with `nix build .#installer-iso` and writes it to the stick.
    packages.${system} = {
      installer-iso = (lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ ./installer/iso.nix ];
      }).config.system.build.isoImage;

      # disko's CLI, for fresh-install.sh. Built from here, it uses this
      # flake's nixpkgs (the `follows` in the inputs): the one the machines
      # and the installer ISO are built from, so on that ISO everything it
      # needs is already there. `nix run --inputs-from . disko` would build
      # it from disko's own nixpkgs instead — hundreds of MiB more to
      # download, and a compiler, which a live ISO's RAM can't hold.
      #
      # Its package.nix reads `stdenv.isDarwin`, deprecated in nixpkgs (an
      # evaluation warning every time; upstream still has it). The override
      # hands it the current attribute's answer under the old name — it's
      # only used for that, so the package itself doesn't change.
      disko = inputs.disko.packages.${system}.disko.override {
        stdenv = nixpkgs.legacyPackages.${system}.stdenv // {
          isDarwin = nixpkgs.legacyPackages.${system}.stdenv.hostPlatform.isDarwin;
        };
      };
    };
  };
}
