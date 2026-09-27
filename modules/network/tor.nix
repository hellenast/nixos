{ pkgs, ... }:

# The Tor daemon (client only, SOCKS proxy on 127.0.0.1:9050) and a
# "Vesktop (Tor)" launcher that sends Vesktop through it. Same purpose as
# the VPN launcher in protonvpn.nix — getting around Discord's regional
# block on video sharing — but through Tor instead.

let
  # Uses Chromium's own --proxy-server flag (Vesktop is Electron), which
  # also sends DNS lookups through the proxy, so nothing leaks. torsocks
  # doesn't work here: its LD_PRELOAD hooks miss Chromium's network stack,
  # and Vesktop just hangs with no window. A SOCKS proxy also needs none of
  # protonvpn.nix's namespace plumbing.
  torVesktop = pkgs.writeShellScriptBin "tor-vesktop" ''
    exec vesktop --proxy-server="socks5://127.0.0.1:9050" "$@"
  '';

  torVesktopDesktopItem = pkgs.makeDesktopItem {
    name = "tor-vesktop";
    desktopName = "Vesktop (Tor)";
    exec = "${torVesktop}/bin/tor-vesktop";
    icon = "vesktop";
    categories = [ "Network" ];
  };
in
{
  services.tor = {
    enable = true;
    client.enable = true;
  };

  environment.systemPackages = [
    torVesktop             # `tor-vesktop`: Vesktop through the Tor SOCKS proxy
    torVesktopDesktopItem  # its "Vesktop (Tor)" launcher entry
  ];
}
