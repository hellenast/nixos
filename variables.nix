{
  # Settings shared by every machine. What differs between them (laptop or
  # not, GPUs, disk, keyboard, monitors, modules left out) is in each one's
  # hosts/<name>/variables.nix, which can also override anything here; its
  # hostname is the folder's name. flake.nix merges the two and threads the
  # result into every module as specialArgs — see docs/machines.md.

  # --- Identity ---
  # Login username and its human-readable description
  # (users.users.*.description).
  username = "hyena";
  userDescription = "Hyena";

  # --- Time / locale ---
  # See `timedatectl list-timezones` for valid timeZone values, and
  # `localectl list-locales` for defaultLocale.
  timeZone = "America/Sao_Paulo";
  defaultLocale = "en_US.UTF-8";

  # --- Appearance ---
  # Cursor theme, applied both via home-manager (GTK/X11, modules/home/default.nix)
  # and natively in Hyprland (modules/home/hyprland.nix). Must be a theme
  # pkgs.bibata-cursors provides — or swap the package too for another theme.
  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = 24;
}
