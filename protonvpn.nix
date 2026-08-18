{ config, pkgs, lib, username, ... }:

let
  # --- Constants ---

  # Everything Proton-VPN-related lives in its own network namespace, so
  # only apps explicitly launched into it are affected — the rest of the
  # system keeps using the normal default route untouched. This is the
  # standard "netns + veth + wg-quick inside the netns" split-tunnel
  # pattern; ProtonVPN's own Linux client doesn't support per-app split
  # tunneling, so this is the way to get it on NixOS.
  netns = "protonvpn";

  vethHost = "pvpn-host"; # host end of the veth pair
  vethNs = "pvpn-ns";     # netns end of the veth pair
  hostAddr = "10.10.10.1";
  nsAddr = "10.10.10.2";
  nsSubnet = "10.10.10.0/24";

  # WireGuard config downloaded from ProtonVPN's dashboard (Downloads ->
  # WireGuard configuration). Decrypted by sops-nix (see secrets.nix) into
  # /run/secrets/protonvpn-conf at activation time — a tmpfs path, root-only
  # (0400), gone on reboot — rather than the plain, world-readable file at
  # /etc/protonvpn/proton.conf this used to be. The encrypted source of
  # truth is secrets/secrets.yaml, safe to commit to this repo.
  wgConfPath = config.sops.secrets."protonvpn-conf".path;
  wgInterface = "protonvpn"; # wg-quick derives this from the conf's basename (secrets.nix pins the path to .../protonvpn.conf)

  # ProtonVPN's internal DNS resolver, only reachable once the tunnel is
  # up — matches the `DNS = ...` line in configs downloaded from their
  # dashboard. If a downloaded config ever shows a different DNS line,
  # update this to match.
  vpnDns = "10.2.0.1";

  # --- Apps that should go through the VPN ---
  # Each entry gets its own "<Name> (VPN)" launcher alongside the app's
  # normal one, so both are pickable from the app grid/rofi — the normal
  # launcher keeps using the default route, this one runs the same command
  # inside the ProtonVPN namespace. `command` must be on $PATH already
  # (i.e. the underlying package is installed somewhere else, e.g.
  # home.nix). Add entries here for whichever apps should be VPN-only.
  apps = [
    { name = "Vesktop"; command = "vesktop"; icon = "vesktop"; }
    # { name = "qBittorrent"; command = "qbittorrent"; icon = "qbittorrent"; }
  ];

  # Vars that need to survive the trip into the namespace, for anything
  # GUI-related launched via protonvpn-run to actually look/work right
  # (Wayland/X11 connection, D-Bus/PulseAudio session, cursor theme+size).
  passthroughEnvVars = [
    "WAYLAND_DISPLAY" "DISPLAY" "XDG_RUNTIME_DIR" "DBUS_SESSION_BUS_ADDRESS"
    "PULSE_SERVER" "XCURSOR_THEME" "XCURSOR_SIZE" "GTK_THEME"
  ];

  protonvpnRun = pkgs.writeShellScriptBin "protonvpn-run" ''
    # The outer sudo hop resets the environment by default (env_reset), so
    # without SETENV + explicitly forwarding each var here, they'd already
    # be gone before the inner `sudo -u --preserve-env` even runs — that
    # was the cause of both the huge cursor and the missing tray icon.
    exec sudo -n \
      ${lib.concatMapStringsSep " " (v: "${v}=\"\${${v}}\"") passthroughEnvVars} \
      ${pkgs.iproute2}/bin/ip netns exec ${netns} \
      sudo -u "$USER" \
      --preserve-env=${lib.concatStringsSep "," passthroughEnvVars} \
      -- "$@"
  '';

  # wg-quick calls `resolvconf -a/-d ...` itself to manage DNS, and fails
  # the whole service if that binary isn't found. We don't want its DNS
  # management anyway — DNS for the namespace is already handled
  # statically below via /etc/netns/${netns}/resolv.conf — so this is just
  # a no-op stand-in to keep that call from failing wg-quick.
  resolvconfShim = pkgs.writeShellScriptBin "resolvconf" "exit 0";

  vpnDesktopItems = map (app: pkgs.makeDesktopItem {
    name = "protonvpn-${app.command}";
    desktopName = "${app.name} (VPN)";
    exec = "${protonvpnRun}/bin/protonvpn-run ${app.command}";
    icon = app.icon or app.command;
    categories = [ "Network" ];
  }) apps;
in
{
  environment.systemPackages = [
    pkgs.wireguard-tools # wg / wg-quick, also handy for `wg show` troubleshooting
    protonvpnRun
  ] ++ vpnDesktopItems;

  # Only this specific netns-exec command gets NOPASSWD — not a general
  # sudo grant. The inner `sudo -u "$USER"` immediately drops back out of
  # root once inside the namespace, so protonvpn-run never actually hands
  # out a root shell.
  security.sudo.extraRules = [
    {
      users = [ username ];
      commands = [
        {
          command = "${pkgs.iproute2}/bin/ip netns exec ${netns} *";
          options = [ "NOPASSWD" "SETENV" ];
        }
      ];
    }
  ];

  # Needed for the host to NAT/forward the netns's tunnel-setup traffic
  # (the WireGuard handshake UDP packets themselves, before the tunnel is
  # up) out through the host's real network — nothing else on this
  # single-user desktop asks for forwarding, so this is scoped as tightly
  # as a global sysctl gets.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall.extraCommands = ''
    iptables -t nat -A POSTROUTING -s ${nsSubnet} -j MASQUERADE
    iptables -A FORWARD -i ${vethHost} -j ACCEPT
    iptables -A FORWARD -o ${vethHost} -j ACCEPT
  '';
  networking.firewall.extraStopCommands = ''
    iptables -t nat -D POSTROUTING -s ${nsSubnet} -j MASQUERADE || true
    iptables -D FORWARD -i ${vethHost} -j ACCEPT || true
    iptables -D FORWARD -o ${vethHost} -j ACCEPT || true
  '';

  # DNS for anything run inside the namespace (both wg-quick itself and
  # apps launched via protonvpn-run): `ip netns exec` automatically
  # bind-mounts /etc/netns/<name>/* over the matching /etc/* path for
  # whatever it runs, without touching the host's real /etc/resolv.conf.
  environment.etc."netns/${netns}/resolv.conf".text = ''
    nameserver ${vpnDns}
  '';

  # Namespace + veth pair, brought up once at boot and left alone.
  systemd.services.protonvpn-netns = {
    description = "ProtonVPN: network namespace + veth pair";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ip netns add ${netns}
      ip link add ${vethHost} type veth peer name ${vethNs}
      ip link set ${vethNs} netns ${netns}

      ip addr add ${hostAddr}/24 dev ${vethHost}
      ip link set ${vethHost} up

      ip netns exec ${netns} ip addr add ${nsAddr}/24 dev ${vethNs}
      ip netns exec ${netns} ip link set ${vethNs} up
      ip netns exec ${netns} ip link set lo up
      ip netns exec ${netns} ip route add default via ${hostAddr}
    '';
    preStop = ''
      ip netns del ${netns} || true
      ip link del ${vethHost} || true
    '';
  };

  # WireGuard tunnel, created directly inside the namespace above (rather
  # than on the host and moved in) so wg-quick's own routing-table
  # handling — which avoids a routing loop between "route the handshake
  # packets to Proton's server" and "route everything through the tunnel"
  # — works exactly as it would on a normal host, just scoped to this
  # namespace's own routing table.
  systemd.services.protonvpn-wg = {
    description = "ProtonVPN: WireGuard tunnel inside network namespace";
    after = [ "protonvpn-netns.service" ];
    requires = [ "protonvpn-netns.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 pkgs.wireguard-tools resolvconfShim ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip netns exec ${netns} ${pkgs.wireguard-tools}/bin/wg-quick up ${wgConfPath}";
      ExecStop = "${pkgs.iproute2}/bin/ip netns exec ${netns} ${pkgs.wireguard-tools}/bin/wg-quick down ${wgConfPath}";
    };
  };
}
