{ config, pkgs, lib, username, ... }:

{
  # I chose Drawing over Pinta since it doesn't pull in a Mono/.NET
  # runtime, keeping its closure much smaller. nixpkgs' vlc bundles its own
  # ffmpeg/libav build, so it already handles the common codecs
  # (H.264/H.265/VP9/AV1, AAC/MP3/FLAC, ...) without extra packages.
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      vlc # video + audio playback (default handler for both — see mimeApps below)
      krita # image editing
      drawing # lightweight GNOME paint-style app for quick crop/rotate/basic-brush edits
      cheese # webcam snapshots/video and basic effects
    ];

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "video/mp4" = [ "vlc.desktop" ];
        "video/x-matroska" = [ "vlc.desktop" ];
        "video/webm" = [ "vlc.desktop" ];
        "video/quicktime" = [ "vlc.desktop" ];
        "video/mpeg" = [ "vlc.desktop" ];
        "video/x-msvideo" = [ "vlc.desktop" ];
        "video/ogg" = [ "vlc.desktop" ];
        "audio/mpeg" = [ "vlc.desktop" ];
        "audio/mp4" = [ "vlc.desktop" ];
        "audio/flac" = [ "vlc.desktop" ];
        "audio/ogg" = [ "vlc.desktop" ];
        "audio/x-wav" = [ "vlc.desktop" ];
        "audio/aac" = [ "vlc.desktop" ];
        "audio/x-m4a" = [ "vlc.desktop" ];
      };
    };
  };
}
