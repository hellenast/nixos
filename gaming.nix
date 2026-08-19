{ config, pkgs, lib, ... }:

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

  # Needs its own enable to install the binary and the setuid wrapper
  # (capSysNice) that lets gamescope renice itself for lower latency.
  programs.gamescope = {
    enable = true;
    capSysNice = true;
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
}
