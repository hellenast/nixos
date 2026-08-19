{
  # --- Identity ---
  # Login username, its human-readable description (users.users.*.description),
  # and the machine's own hostname. This is threaded into every module as a
  # specialArg (see flake.nix), so it's the one place to change them.
  # `nixos-rebuild switch --flake .#` (no name after `#`) picks the
  # `nixosConfigurations` attribute matching the machine's actual hostname,
  # so hostname here has to match whatever machine you're deploying to.
  username = "hyena";
  userDescription = "Hyena";
  hostname = "hyena";

  # --- Time / locale / keyboard ---
  # See `timedatectl list-timezones` for valid timeZone values, and
  # `localectl list-locales` / `localectl list-keymaps` for locale/keyMap.
  timeZone = "America/Sao_Paulo";
  defaultLocale = "en_US.UTF-8";
  # TTY keymap — only affects plain virtual consoles, not the graphical
  # session (that's keyboardLayout/keyboardVariant below).
  consoleKeyMap = "us-acentos";
  # Hyprland keyboard layout/variant (XKB names — `localectl list-x11-keymap-variants <layout>`
  # to see what's available for a given layout). "intl" adds dead-key
  # composition (e.g. ' + c -> ç); use "" for a plain layout with none of that.
  keyboardLayout = "us";
  keyboardVariant = "intl";

  # --- Monitors ---
  # Hyprland/greetd output names for a two-monitor desk setup — find yours
  # with `hyprctl monitors` (once already running) or `wlr-randr`. If you
  # only have one monitor, point secondaryMonitor.output at the same name
  # as primaryMonitor.output and drop the second `hl.monitor` block in
  # home.nix's hypr-user.lua (search for "secondaryMonitor").
  primaryMonitor = {
    output = "DP-2";
    mode = "2560x1440@165";
    position = "0x0";
  };
  secondaryMonitor = {
    output = "HDMI-A-1";
    mode = "2560x1080@60";
    position = "2560x0";
    # Hyprland transform value: 0 = normal, 1 = 90°, 2 = 180°, 3 = 270°.
    # 3 here because this monitor is physically mounted rotated.
    transform = 3;
  };

  # --- Appearance ---
  # Cursor theme, applied both via home-manager (GTK/X11) and natively in
  # Hyprland (see home.nix). Must be a theme name pkgs.bibata-cursors
  # actually provides, or swap the package too if you want a different theme.
  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = 24;
}
