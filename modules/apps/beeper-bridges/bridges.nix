{ lib, pkgs, ... }:

# Self-hosted Beeper bridges (docs/beeper-bridges.md). Accounts connected
# through them don't count against Beeper's account limit, and they keep
# working in the Beeper apps as usual.
#
# Each bridge runs under Beeper's own bridge manager, `bbctl run`, which
# registers it with the account and writes its config (keeping it current
# with Beeper's template). The bridge binary itself comes from nixpkgs
# instead of the build bbctl would download (--custom-startup-command), so
# bridges update with the flake like everything else. Bridges connect out to
# Beeper over a websocket: nothing listens on the internet.
#
# No Google Chat: its bridge (mautrix-googlechat) hasn't had a release since
# July 2024, and against today's Google Chat it logs in but syncs no chats.
# That account stays on Beeper's own servers instead, within the free plan's
# limit.
let
  home = "/var/lib/beeper-bridges";
  bbctl = pkgs.callPackage ./pkgs/bbctl.nix { };

  # The bridgev2 ones use goolm, mautrix-go's pure-Go Olm, instead of libolm,
  # which nixpkgs marks insecure (its AES and Curve25519 code isn't
  # constant-time). Discord can't: its bridge is the older kind, on a mautrix
  # version whose encryption is libolm-only. It gets a libolm with that mark
  # lifted, for it alone — a global permittedInsecurePackages wouldn't merge
  # with apps/dev.nix's (nixpkgs config lists replace each other) and would
  # allow it system-wide.
  whatsapp = pkgs.mautrix-whatsapp.override { withGoolm = true; };
  signal = pkgs.mautrix-signal.override { withGoolm = true; };
  linkedin = pkgs.callPackage ./pkgs/mautrix-linkedin.nix { };
  olm = pkgs.olm.overrideAttrs (old: { meta = old.meta // { knownVulnerabilities = [ ]; }; });
  discord = pkgs.mautrix-discord.override { inherit olm; };

  # One bridge per account type, except Discord: its bridge (still the older,
  # pre-bridgev2 kind) takes one login each, so the second Discord account
  # gets a second bridge. The bridgev2 ones (WhatsApp, Signal, LinkedIn) take
  # any number of logins. Names are what Beeper shows in its bridge list;
  # bbctl wants them to start with "sh-".
  bridges = {
    sh-whatsapp = { type = "whatsapp"; command = lib.getExe whatsapp; };
    sh-discord = { type = "discord"; command = lib.getExe discord; };
    sh-discord2 = { type = "discord"; command = lib.getExe discord; };
    sh-linkedin = { type = "linkedin"; command = lib.getExe linkedin; };
    sh-signal = { type = "signal"; command = lib.getExe signal; };
  };

  # Written by `beeper-bbctl login`; until then the bridges have no account
  # to register with, so they don't start.
  loginMarker = "${home}/.logged-in";

  # bbctl as the bridges' user, with their data. `beeper-bbctl login` is
  # the one-time setup (docs/beeper-bridges.md); whoami/delete work as usual.
  beeperBbctl = pkgs.writeShellScriptBin "beeper-bbctl" ''
    set -e
    ${pkgs.util-linux}/bin/runuser -u beeper-bridges -- env HOME=${home} ${lib.getExe bbctl} "$@"
    if [ "$1" = login ]; then
      ${pkgs.util-linux}/bin/runuser -u beeper-bridges -- touch ${loginMarker}
      systemctl restart beeper-bridges.target
      echo "Bridges started: systemctl status 'beeper-bridge-*'"
    fi
  '';
in
{
  users.users.beeper-bridges = {
    isSystemUser = true;
    group = "beeper-bridges";
    inherit home;
    createHome = true;
  };
  users.groups.beeper-bridges = { };

  environment.systemPackages = [ beeperBbctl ];

  systemd.targets.beeper-bridges = {
    description = "Self-hosted Beeper bridges";
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services = lib.mapAttrs' (name: bridge: lib.nameValuePair "beeper-bridge-${name}" {
    description = "Beeper bridge ${name} (${bridge.type})";
    wantedBy = [ "beeper-bridges.target" ];
    partOf = [ "beeper-bridges.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = loginMarker;
    # Bridges convert some media (stickers, GIFs, voice) with ffmpeg.
    path = [ pkgs.ffmpeg ];
    environment.HOME = home;
    serviceConfig = {
      User = "beeper-bridges";
      Group = "beeper-bridges";
      WorkingDirectory = home;
      ExecStart = "${lib.getExe bbctl} run --type ${bridge.type} --custom-startup-command ${bridge.command} ${name}";
      Restart = "always";
      RestartSec = 30;

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ home ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
    };
  }) bridges;
}
