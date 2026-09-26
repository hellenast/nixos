{ config, pkgs, lib, inputs, ... }:

let
  # Millennium (see flake.nix) — the Steam client modding framework the
  # caelestia Steam theme in home.nix runs under. Built with Millennium's own
  # pinned nixpkgs, same as its flake does, rather than taken from its
  # `packages` output: upstream's v3.5.0 packaging missed updating the hash
  # of its Bun dependencies (the v3.5.0 sources resolve to exactly the
  # v3.4.1 set — SteamClientHomebrew/Millennium#907 fixes it upstream), so
  # the build fails as shipped. Patched the same way as rules.lua in
  # home.nix: a targeted string replace on the pinned source, which becomes
  # a no-op once the pin moves past the fix.
  millenniumPkgs = import inputs.millennium.inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  millennium = millenniumPkgs.callPackage (builtins.toFile "millennium.nix" (
    builtins.replaceStrings
      [ "sha256-mAM2qhb0TOzPosejOcG2VegDkbEmY3JF8lkKgDpVjA0=" ]
      [ "sha256-iPdEl5GH0cXjn1EUdYutqxdMwdRXms+eXCEIwZ3xeLY=" ]
      (builtins.readFile "${inputs.millennium}/millennium.nix")
  )) { inherit (inputs.millennium.inputs) millennium-src; };
in
{
  programs.steam = {
    enable = true;
    # Steam with Millennium injected, through Millennium's own wrapper
    # (steam.nix in the input) applied to my nixpkgs' Steam rather than the
    # one from Millennium's pinned nixpkgs. It adds Millennium's libraries to
    # Steam's FHS env and, on every launch, points
    # ~/.local/share/Steam/ubuntu12_{32,64}/libXtst.so.6 at Millennium's
    # bootstrap library — that's the hook Steam loads it through. It only
    # touches the Steam client UI, not games. If I ever drop this again,
    # those two symlinks have to be deleted by hand, or Steam keeps trying to
    # load a library that's no longer there.
    package = pkgs.callPackage "${inputs.millennium}/steam.nix" { inherit millennium; };
    remotePlay.openFirewall = true;      # opens ports for Remote Play
    dedicatedServer.openFirewall = true; # opens ports for hosting game servers
    gamescopeSession = {
      enable = true;
      # -f = fullscreen. Every game I launch from this Steam session fills
      # the screen automatically, since gamescope is the only compositor
      # for the session — there's no window manager for a game to
      # "un-fullscreen" into.
      args = [ "-f" "--adaptive-sync" ];
    };
  };

  # capSysNice off: the setuid wrapper it installs breaks when gamescope is
  # launched from a Steam per-game Launch Options command (e.g. `gamescope
  # ... -- %command%`) — Steam sets no_new_privs on that process chain,
  # which makes the kernel refuse the wrapper's file capability, so
  # gamescope exits immediately with "failed to inherit capabilities:
  # Operation not permitted". gamemode (below) already reduces niceness for
  # games, so the wrapper isn't worth losing per-game gamescope over.
  programs.gamescope = {
    enable = true;
    capSysNice = false;
  };

  # Auto-applies perf tweaks (CPU governor, I/O priority, etc.) while a game
  # runs. Steam picks this up on its own once enabled; for anything else, I
  # wrap the launch command manually under Properties -> General -> Launch
  # Options:
  #   gamemoderun %command%
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        renice = 10; # nice level applied to the game process
      };
    };
  };

  environment.systemPackages = with pkgs; [
    # Minecraft Java Edition launcher (FOSS, MultiMC-derived). Manages its
    # own bundled JRE and per-instance mod loaders (Fabric/Forge/etc.), so
    # I don't need a separate JDK package here. Microsoft account sign-in
    # and instance/mod setup happen inside it — see Manual setup in
    # README.md.
    prismlauncher

    # Minecraft Bedrock Edition, the real Windows (GDK) build running
    # under steam-run/Proton with native Xbox sign-in — see flake.nix for
    # why I landed here after mcpelauncher-ui-qt and Waydroid (still kept
    # around in waydroid.nix for other Android apps, just not Bedrock)
    # both turned out to be dead ends. Ships no game files itself; the
    # first run downloads Minecraft from Microsoft under my own account —
    # see Manual setup in README.md.
    inputs.bedrock-on-linux.packages.${pkgs.system}.default
  ];
}
