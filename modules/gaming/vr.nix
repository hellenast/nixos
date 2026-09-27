{ ... }:

{
  # ALVR streams SteamVR games (Beat Saber, VRChat, ...) from this PC to a
  # standalone headset (Quest, etc.) over Wi-Fi. Steam (steam.nix) runs the
  # games; ALVR only carries video and tracking between them and the
  # headset. openFirewall opens 9943/9944 TCP+UDP for the server and client
  # discovery. Headset pairing is manual — see docs/gaming.md.
  programs.alvr = {
    enable = true;
    openFirewall = true;
  };
}
