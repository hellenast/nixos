{ config, pkgs, lib, username, ... }:

# Per-app ProtonVPN split tunnelling. A dedicated network namespace holds a
# WireGuard tunnel; only apps launched into it (the "<Name> (VPN)" launchers)
# use the VPN, and everything else keeps the normal route. ProtonVPN's own
# Linux client can't do per-app split tunnelling.
#
# Needs system/secrets.nix for the WireGuard config. Setup, verification and
# troubleshooting: docs/protonvpn.md.

let
  # --- Constants ---

  # The standard "netns + veth pair + wg-quick inside the netns" pattern:
  # the veth pair links the namespace to the host, which NATs its traffic
  # out so the tunnel can reach Proton's server.
  netns = "protonvpn";

  vethHost = "pvpn-host"; # host end of the veth pair
  vethNs = "pvpn-ns";     # netns end of the veth pair
  hostAddr = "10.10.10.1";
  nsAddr = "10.10.10.2";
  nsSubnet = "10.10.10.0/24";

  # The WireGuard config from ProtonVPN's dashboard, kept encrypted in
  # secrets/secrets.yaml and decrypted by sops-nix (system/secrets.nix) to
  # /run/secrets/protonvpn.conf — root-only, on a tmpfs.
  wgConfPath = config.sops.secrets."protonvpn-conf".path;
  # wg-quick names the interface after the config file's basename.
  wgInterface = "protonvpn";

  # ProtonVPN's internal DNS resolver, only reachable once the tunnel is
  # up — matches the `DNS = ...` line in configs downloaded from their
  # dashboard. If a downloaded config ever shows a different DNS line,
  # update this to match.
  vpnDns = "10.2.0.1";

  # --- Apps that should go through the VPN ---
  # Each entry gets a "<Name> (VPN)" launcher next to the app's normal one,
  # running the same command inside the namespace. This doesn't install the
  # app: `command` must already be on $PATH (e.g. vesktop, from
  # home/apps/vesktop.nix).
  apps = [
    { name = "Vesktop"; command = "vesktop"; icon = "vesktop"; }
    # { name = "qBittorrent"; command = "qbittorrent"; icon = "qbittorrent"; }
  ];

  # Session variables a GUI app needs to work inside the namespace: display
  # connection, D-Bus/PulseAudio session, cursor theme and size.
  passthroughEnvVars = [
    "WAYLAND_DISPLAY" "DISPLAY" "XDG_RUNTIME_DIR" "DBUS_SESSION_BUS_ADDRESS"
    "PULSE_SERVER" "XCURSOR_THEME" "XCURSOR_SIZE" "GTK_THEME"
  ];

  protonvpnRun = pkgs.writeShellScriptBin "protonvpn-run" ''
    # Two sudo hops: root to enter the namespace, then back to the user.
    # The outer hop resets the environment (env_reset), so each variable is
    # passed explicitly as VAR=value (allowed by SETENV in the sudo rule
    # below) and then preserved by the inner hop. Without this, apps come up
    # with a huge cursor and no tray icon.
    exec sudo -n \
      ${lib.concatMapStringsSep " " (v: "${v}=\"\${${v}}\"") passthroughEnvVars} \
      ${pkgs.iproute2}/bin/ip netns exec ${netns} \
      sudo -u "$USER" \
      --preserve-env=${lib.concatStringsSep "," passthroughEnvVars} \
      -- "$@"
  '';

  # wg-quick runs `resolvconf` to set DNS and fails if it's missing. DNS for
  # the namespace is already set statically (/etc/netns/<netns>/resolv.conf,
  # below), so a no-op stand-in is all it needs.
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
    protonvpnRun          # `protonvpn-run <cmd>`: runs a command inside the VPN namespace
  ] ++ vpnDesktopItems;

  # Passwordless sudo for exactly this netns-exec command, not in general.
  # protonvpn-run's inner `sudo -u "$USER"` drops root again inside the
  # namespace, so it never hands out a root shell. SETENV lets the outer
  # hop accept the VAR=value assignments (see protonvpnRun above).
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

  # The host has to forward and NAT the namespace's traffic — the WireGuard
  # packets to Proton's server — out through its real network. The
  # firewall rules below limit the forwarding to the veth pair.
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

  # DNS inside the namespace, for wg-quick and the apps alike:
  # `ip netns exec` bind-mounts /etc/netns/<name>/* over the matching /etc/*
  # paths for whatever it runs, leaving the host's resolv.conf alone.
  environment.etc."netns/${netns}/resolv.conf".text = ''
    nameserver ${vpnDns}
  '';

  # The namespace and veth pair, created once at boot.
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

  # The tunnel, brought up by wg-quick inside the namespace (not created on
  # the host and moved in). That way wg-quick's usual routing setup — which
  # keeps the handshake packets to Proton's server from being routed into
  # the tunnel itself — works as on a normal host, on the namespace's own
  # routing table.
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
