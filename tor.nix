{ pkgs, ... }:

let
  # Vesktop/Discord is Electron (Chromium), and Chromium implements its own
  # network stack with raw syscalls that bypass the libc functions
  # LD_PRELOAD-based wrappers like torsocks hook into — torsocks silently
  # hangs Electron with no window and no error. Chromium's own
  # --proxy-server flag is the correct mechanism: it's handled natively by
  # Chromium's network stack, including proxying DNS lookups through the
  # SOCKS proxy (no leak), and needs no netns/veth plumbing like
  # protonvpn.nix, since Tor already exposes a local SOCKS proxy rather
  # than requiring a routed tunnel interface.
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
    torVesktop
    torVesktopDesktopItem
  ];
}
