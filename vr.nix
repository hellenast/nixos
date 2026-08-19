{ config, pkgs, lib, ... }:

{
  # ALVR: streams SteamVR (Beat Saber, VRChat) from this PC to my
  # standalone headset (Quest, etc.) over Wi-Fi. openFirewall punches the
  # 9943/9944 TCP+UDP ports the ALVR server and its client-discovery step
  # need. Steam itself (enabled in gaming.nix) is what actually runs
  # SteamVR/Beat Saber/VRChat; ALVR just gets the headset's video+tracking
  # to and from it. Roblox via Sober doesn't touch any of this — it's a
  # Flatpak, not a VR app.
  programs.alvr = {
    enable = true;
    openFirewall = true;
  };
}
