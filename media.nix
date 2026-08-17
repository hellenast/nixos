{ config, pkgs, lib, username, ... }:

{
  # VLC (video + audio, default handler for both — see mimeApps below),
  # Krita (image editing), Drawing (a lightweight GNOME paint-style app for
  # quick crop/rotate/basic-brush edits — no Mono/.NET runtime pulled in,
  # unlike Pinta, so it's a much smaller closure for something meant to
  # stay minimal). nixpkgs' vlc bundles its own ffmpeg/libav build, so it
  # already handles the common codecs (H.264/H.265/VP9/AV1, AAC/MP3/FLAC,
  # ...) without extra packages.
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      vlc
      krita
      drawing
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
