{ config, pkgs, lib, inputs, username, userDescription, hostname, ... }:

let
  # regreet (below) picks sessions to launch from wayland-sessions .desktop
  # entries — nothing installs one for Hyprland on its own, since this setup
  # never used a session-file-driven greeter before (greetd execed
  # start-hyprland directly). This is the officially supported way to
  # register one (services.displayManager.sessionPackages), same pattern
  # nixpkgs' own river/dwl modules use for themselves.
  hyprlandSession = pkgs.writeTextFile {
    name = "hyprland-wayland-session";
    destination = "/share/wayland-sessions/hyprland.desktop";
    text = ''
      [Desktop Entry]
      Name=Hyprland
      Comment=Hyprland compositor session
      Exec=start-hyprland
      Type=Application
    '';
    # services.displayManager.sessionPackages requires this — it's how NixOS
    # knows which session name(s) this package makes available, matching
    # the .desktop file's own basename above.
    passthru.providedSessions = [ "hyprland" ];
  };

  # regreet's own NixOS module hosts it in cage by default, but cage can
  # only pick "last enumerated output" or "extend across all outputs" — no
  # way to name a specific monitor, and "last" landed on the HDMI ultrawide
  # here instead of the main DP-2 display (confirmed live). sway *can*
  # target an output by name, so this is a minimal, single-purpose sway
  # config used only to host the greeter: disabling HDMI-A-1 outright is
  # what actually guarantees regreet lands on DP-2 (rather than a
  # `for_window ... move to output` rule, which depends on correctly
  # guessing regreet's app_id) — with only one output left enabled, there's
  # nowhere else for it to go. No bar, no gaps, no keybindings at all
  # (nothing here to hijack — this session has nothing else running in it
  # to switch to), and the single `exec` line running regreet is what
  # decides when the session ends: once regreet exits (successful login or
  # otherwise), `swaymsg exit` tears sway down and hands control back to
  # greetd, the same way cage tears down when its one wrapped app exits.
  greeterSwayConfig = pkgs.writeText "greeter-sway-config" ''
    output DP-2 enable
    output HDMI-A-1 disable

    default_border none
    for_window [app_id=".*"] fullscreen enable

    exec "${lib.getExe config.services.displayManager.regreet.package}; swaymsg exit"
  '';
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # If I ever end up on legacy BIOS instead of UEFI, delete the two lines
  # above and use:
  # boot.loader.grub.enable = true;
  # boot.loader.grub.device = "/dev/sda";

  # --- Memory management ---
  # Default is 60 — fine for a typical amount of RAM, but this machine has
  # 60GB, so the kernel proactively swapping out idle pages that early is
  # pure waste. Lower means "only swap once actually under real memory
  # pressure" instead of preemptively; 8GB of swap (hardware-configuration.
  # nix) was never sized for hibernation anyway (sleep/suspend is disabled
  # outright below), so this is purely about avoiding unnecessary swap
  # I/O, not preserving swap headroom for anything.
  boot.kernel.sysctl."vm.swappiness" = 10;

  # zram: compressed swap living in RAM instead of on disk — no disk I/O,
  # and compression means it holds more than its nominal size in actual
  # data. Given the kernel already prefers whichever swap device has the
  # higher priority, and zram's default priority (5) already beats the
  # disk swap partition's (-2, unset in hardware-configuration.nix), this
  # naturally becomes the first line of defense — the disk swap partition
  # only gets touched if zram itself fills up too, which at 50% of 60GB
  # RAM (the module's default, left as-is) is a lot of headroom.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # --- Networking ---
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  # --- Time / locale ---
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  # TTY keymap to match the intl dead-key layout Hyprland uses (see
  # home.nix -> caelestia/hypr-user.lua). Only affects plain virtual
  # consoles, not the graphical session.
  console.keyMap = "us-acentos";

  # --- Nix ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Garbage collection: every generation (system + home-manager) pins its
  # own closure in the store forever until something collects it, so this
  # only grows unbounded otherwise — update-flake.sh (home.nix) bumps
  # inputs often enough that old generations pile up fast. Daily sweep,
  # keeping a week of history (enough to roll back a bad rebuild from a
  # few days ago) and deleting anything older.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # --- AMD GPU / graphics ---
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  # amdgpu is the default kernel driver on modern kernels, nothing extra
  # needed. If I ever end up on a very new AMD GPU that isn't recognized:
  # boot.initrd.kernelModules = [ "amdgpu" ];

  # --- Desktop session: Hyprland + greetd ---
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # A themed GTK login screen (regreet, run inside a minimal sway session —
  # see greeterSwayConfig above) prompts for a password on every
  # boot/logout before Hyprland ever starts — no more autologin, and no
  # more caelestia locking the screen again immediately on session start
  # (see home.nix -> caelestia/hypr-user.lua, that hyprland.start hook is
  # gone now that this covers the same job at the actual entry point).
  #
  # Went with regreet over tuigreet (the first attempt here) specifically
  # because tuigreet is a bare terminal UI — plain text on a black
  # background, no theming to speak of. regreet is an actual GTK app: it
  # gets a real background/cursor/icon theme and font, set below, though it
  # can't pick up caelestia's *dynamic* colors the way in-session GTK apps
  # do — it runs before the session (and caelestia) exist at all.
  services.displayManager.regreet = {
    enable = true;
    cursorTheme = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
    };
    # regreet defaults to plain Adwaita, which (unlike the dark caelestia
    # theme everywhere else) renders as a light/white window — this is the
    # actual GTK dark-mode preference, not a different theme name; modern
    # Adwaita follows it instead of needing a separate "-dark" theme.
    settings.GTK.application_prefer_dark_theme = true;
  };

  # Overrides the module's own cage-based default (see greeterSwayConfig
  # above for why) — a plain assignment here beats the module's mkDefault
  # without needing lib.mkForce.
  services.greetd.settings.default_session.command =
    "${pkgs.dbus}/bin/dbus-run-session ${lib.getExe pkgs.sway} --config ${greeterSwayConfig}";

  services.displayManager.sessionPackages = [ hyprlandSession ];

  # Portals: screen share, file pickers, etc. under Wayland.
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland  # Hyprland-specific portal backend (screen share, screenshot picker)
      pkgs.xdg-desktop-portal-gtk       # GTK portal backend (file pickers, other common dialogs)
    ];
    config.common.default = "*";
  };

  # Polkit prompts (GUI privilege dialogs, NetworkManager applet, etc.)
  security.polkit.enable = true;
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  # --- Power management ---
  # I never want this machine to sleep on its own. Masking the sleep
  # targets outright means nothing can trigger them — not a stray
  # `systemctl suspend`, not the power button, not the lid switch. More
  # reliable than editing hypridle.conf, since that would only cover the
  # idle-timeout path (and this setup doesn't even use hypridle — see
  # home.nix for why).
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # logind handles the lid switch/power key directly, separately from the
  # sleep targets above, so it needs telling too.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # --- Audio: pipewire ---
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # --- Fonts ---
  fonts.packages = with pkgs; [
    material-symbols  # icon glyphs used throughout caelestia-shell's UI
    rubik             # caelestia-shell's UI text font
  ];

  # --- Bluetooth ---
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # --- Trash support for Thunar ---
  # Without gvfs, Thunar has no trash:// backend at all, so its Delete
  # action always falls back to permanent deletion (with a confirmation
  # prompt) instead of moving files to ~/.local/share/Trash the way GIO's
  # trash spec expects. This also brings network-mount browsing (sftp://,
  # smb://, ...) and drag-and-drop between apps that expect gvfs, not just
  # trash.
  services.gvfs.enable = true;

  # --- Gaming: see gaming.nix (Steam, gamescope, gamemode) ---

  # --- Flatpak ---
  services.flatpak.enable = true;
  # nix-flatpak's own auto-updater — registers a systemd timer that updates
  # installed Flatpaks (Sober here) in place. Nix itself has nothing to do
  # with keeping Flatpak apps current; this is the one piece of "staying
  # updated" that isn't covered by bumping flake.lock. Daily rather than
  # weekly: Sober/Roblox ships new builds faster than once a week, and
  # Sober refuses to launch at all against a stale build until it's updated.
  services.flatpak.update.auto = {
    enable = true;
    onCalendar = "daily";
  };
  # Also update on every boot, not just once a day — Sober/Roblox ships
  # builds often enough that a same-day gap can still leave it stale, and
  # Sober refuses to launch at all against a stale build. Independent of
  # the timer above (its unit name is a nix-flatpak internal), so it isn't
  # affected by module changes there.
  #
  # Not ordered after flatpak-managed-install.service: that unit is itself
  # After=multi-user.target (it runs late, triggered by activation), so
  # depending on it while also being WantedBy=multi-user.target creates an
  # ordering cycle that systemd resolves by silently dropping this service
  # from the boot. `flatpak update` doesn't need to wait for it anyway.
  systemd.services.flatpak-update-on-boot = {
    description = "Update Flatpak apps on boot";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.flatpak}/bin/flatpak update --system -y";
  };
  services.flatpak.remotes = [
    {
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }
  ];
  services.flatpak.packages = [
    "org.vinegarhq.Sober"
    # Amazfish (Amazfit companion app) lives in amazfit.nix instead.
    # Spotify lives in home.nix instead, as a *user-scope* Flatpak install
    # via nix-flatpak's home-manager module — this system-wide install path
    # (/var/lib/flatpak) is root-owned, which spicetify can't patch any
    # better than the Nix store.
  ];
  services.flatpak.overrides = {
    "org.vinegarhq.Sober" = {
      Context = {
        devices = [ "input" ];
      };
    };
  };

  # --- Users ---
  users.users.${username} = {
    isNormalUser = true;
    description = userDescription;
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "libvirtd" ];
    shell = pkgs.fish;
  };
  programs.fish.enable = true;

  environment.systemPackages = with pkgs; [
    git       # version control
    wget      # command-line downloader
    curl      # command-line HTTP client
    usbutils  # lsusb and friends, for inspecting connected USB devices

    # Audio routing, for patching the Windows VM's Dubbing AI output into
    # the virtual mic (see audio-routing.nix).
    pavucontrol  # GUI mixer/volume control per app and device
    qpwgraph     # GUI PipeWire patchbay, for wiring virtual audio nodes together
  ];

  programs.nix-ld.enable = true;

  # --- Virtualisation: see windows-vm.nix (libvirtd, virt-manager, VM def) ---

  system.stateVersion = "26.11";
}
