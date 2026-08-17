{ config, pkgs, lib, ... }:

{
  # ALVR: streams SteamVR (Beat Saber, VR Chat) from this PC to a
  # standalone headset (Quest, etc.) over Wi-Fi. openFirewall punches the
  # 9943/9944 TCP+UDP ports the ALVR server and its client-discovery step
  # need. Steam itself (enabled in gaming.nix) is what actually runs
  # SteamVR/Beat Saber/VR Chat; ALVR just gets the headset's video+tracking
  # to and from it. Roblox via Sober doesn't touch any of this — it's a
  # flatpak, not a VR app.
  programs.alvr = {
    enable = true;
    openFirewall = true;
  };
}
