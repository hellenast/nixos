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
      # cheese used to be here for webcam snapshots/video and basic effects,
      # but it just silently hangs on Hyprland — no window, no error, CPU
      # spinning at 100% in the "cheese" process. I traced it: cheese's
      # video preview is built on Clutter (via clutter-gtk/clutter-gst),
      # which is long-deprecated upstream and effectively unmaintained, and
      # nixpkgs only builds its Wayland backend, not X11 — so there's no
      # XWayland fallback to force it through either (I tried
      # CLUTTER_BACKEND=x11, which just gets "Unsupported backend" instead
      # of hanging). Nothing here can fix Clutter's own Wayland support.
      # webcamoid is a modern, actively maintained replacement with the
      # same snapshot/video/effects feature set, and it actually opens.
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
  };
}
