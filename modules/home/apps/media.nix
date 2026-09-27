{ pkgs, ... }:

# Media playback, image editing and webcam.
{
  home.packages = with pkgs; [
    # nixpkgs' VLC bundles its own ffmpeg, so the common codecs
    # (H.264/H.265/VP9/AV1, AAC/MP3/FLAC, ...) need no extra packages.
    vlc      # video + audio player (default for both, see below)
    krita    # image editing
    # Quick crop/rotate/annotate; also opens after region screenshots
    # (home/hyprland.nix). Chosen over Pinta, which pulls in a .NET runtime.
    drawing
    # Webcam snapshots/video with effects. Replaces cheese, which hangs on
    # Hyprland: its preview uses the deprecated Clutter toolkit, whose
    # Wayland backend is broken, and nixpkgs doesn't build Clutter's X11
    # backend to fall back to.
    webcamoid
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
}
