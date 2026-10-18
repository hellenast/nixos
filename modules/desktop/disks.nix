{ ... }:

# GNOME Disks: format, partition, encrypt, check (SMART), benchmark and
# image drives. A GTK3 app, so caelestia's GTK theming (adw-gtk3 plus its
# generated gtk.css) already colours it.
{
  # The app, plus its D-Bus service: the .desktop entry is DBusActivatable,
  # so launchers may start it over D-Bus rather than running `gnome-disks`.
  programs.gnome-disks.enable = true;

  # The daemon that does the actual work. desktop/thunar.nix's gvfs already
  # turns it on; set here too so Disks doesn't depend on Thunar. nixpkgs'
  # udisks has the mkfs tools on its own PATH (ext4, FAT, exFAT, NTFS,
  # btrfs, XFS, F2FS), so every type in the format dialog works.
  #
  # Changes to internal drives ask for the password through polkit. The
  # agent that shows that prompt is started from the dots' execs.lua (its
  # path patched in home/hyprland.nix).
  services.udisks2.enable = true;
}
