{ config, pkgs, lib, inputs, ... }:

{
  programs.steam = {
    enable = true;
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
