{ config, pkgs, lib, inputs, username, userDescription, hostname, timeZone, defaultLocale, consoleKeyMap, ... }:

let
  # A Plymouth theme matching caelestia's current "hard" dynamic scheme
  # (~/.local/state/caelestia/scheme.json -> background/primary) instead of
  # a generic third-party palette. I reuse catppuccin-plymouth's mocha
  # assets (lock icon, password-dot field, keyboard/capslock indicators,
  # spinner frames) — that's the `two-step` Plymouth plugin, a proven,
  # built-in-to-plymouth password prompt — but swap in my own colors via a
  # fresh .plymouth ini rather than reskinning the icons myself.
  # Static snapshot, not derived live: I re-run this by hand (new hex
  # values below) if caelestia's scheme ever changes again.
  caelestiaPlymouthTheme = pkgs.runCommand "caelestia-hard-plymouth-theme" { } ''
    themeDir=$out/share/plymouth/themes/caelestia-hard
    mkdir -p "$themeDir"
    cp ${pkgs.catppuccin-plymouth.override { variant = "mocha"; }}/share/plymouth/themes/catppuccin-mocha/*.png "$themeDir"/

    cat > "$themeDir"/caelestia-hard.plymouth <<EOF
    [Plymouth Theme]
    Name=caelestia-hard
    Description=Matches caelestia-shell's "hard" dark scheme
    ModuleName=two-step

    [two-step]
    Font=Noto Sans 12
    TitleFont=Noto Sans Light 30
    ImageDir=$themeDir
    DialogHorizontalAlignment=.5
    DialogVerticalAlignment=.5
    TitleHorizontalAlignment=.5
    TitleVerticalAlignment=.5
    HorizontalAlignment=.5
    VerticalAlignment=.5
    WatermarkHorizontalAlignment=.5
    WatermarkVerticalAlignment=.5
    Transition=none
    TransitionDuration=0.0
    BackgroundStartColor=0x020305
    BackgroundEndColor=0x020305
    ProgressBarBackgroundColor=0x090b0f
    ProgressBarForegroundColor=0xb4c7ed
    MessageBelowAnimation=true

    [boot-up]
    UseEndAnimation=false

    [shutdown]
    UseEndAnimation=false

    [reboot]
    UseEndAnimation=false
    EOF
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

  # I need a systemd-based initrd to actually let Plymouth theme the LUKS
  # passphrase prompt below — the classic initrd shows that prompt as plain
  # text on the console *before* Plymouth ever starts (there's no hook
  # between them), while systemd's own systemd-ask-password mechanism talks
  # to Plymouth directly, which is how every "pretty" LUKS unlock screen
  # (Omarchy included) actually works under the hood.
  boot.initrd.systemd.enable = true;

  # I want a themed splash + LUKS unlock screen instead of plain text —
  # caelestia-matched colors (see caelestiaPlymouthTheme above) instead of
  # a generic NixOS snowflake watermark, since that logo overlay only wires
  # itself up for the stock catppuccin theme names, not my custom one.
  boot.plymouth = {
    enable = true;
    theme = "caelestia-hard";
    themePackages = [ caelestiaPlymouthTheme ];
  };

  # --- Memory management ---
  # Default is 60 — fine for a typical amount of RAM, but my machine has
  # 60GB, so the kernel proactively swapping out idle pages that early is
  # pure waste. Lower means "only swap once actually under real memory
  # pressure" instead of preemptively; my 8GB of swap (hardware-
  # configuration.nix) was never sized for hibernation anyway (sleep/
  # suspend is disabled outright below), so this is purely about avoiding
  # unnecessary swap I/O, not preserving swap headroom for anything.
  boot.kernel.sysctl."vm.swappiness" = 10;

  # zram: compressed swap living in RAM instead of on disk — no disk I/O,
  # and compression means it holds more than its nominal size in actual
  # data. Since the kernel already prefers whichever swap device has the
  # higher priority, and zram's default priority (5) already beats the
  # disk swapfile's (-2, unset in disko.nix), this naturally becomes my
  # first line of defense — the disk swapfile only gets touched if zram
  # itself fills up too, which at 50% of 60GB RAM (the module's default,
  # left as-is) is a lot of headroom.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # --- Networking ---
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  # --- Time / locale ---
  time.timeZone = timeZone;
  i18n.defaultLocale = defaultLocale;

  # TTY keymap to match the intl dead-key layout I use for Hyprland (see
  # home.nix -> caelestia/hypr-user.lua). Only affects plain virtual
  # consoles, not the graphical session. See variables.nix.
  console.keyMap = consoleKeyMap;

  # --- Nix ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Garbage collection: every generation (system + home-manager) pins its
  # own closure in the store forever until something collects it, so this
  # only grows unbounded otherwise — update-flake.sh (home.nix) bumps my
  # inputs often enough that old generations pile up fast. I run a daily
  # sweep, keeping a week of history (enough to roll back a bad rebuild
  # from a few days ago) and deleting anything older.
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
  # amdgpu is the default kernel driver on modern kernels, so nothing extra
  # is needed for the desktop session itself to find/use it. But without
  # this, amdgpu only loads once stage 2 gets around to it — everything
  # before that (Plymouth's splash, the LUKS unlock prompt above) runs on
  # the firmware's plain EFI framebuffer instead, which is what was
  # rendering at the wrong (non-native) resolution for me. Loading amdgpu
  # in the initrd itself gives Plymouth real KMS at the monitor's native
  # resolution from the very first frame.
  boot.initrd.kernelModules = [ "amdgpu" ];

  # --- Desktop session: Hyprland + greetd ---
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # greetd starts Hyprland straight for me, no greeter prompt and no
  # password check of its own — LUKS (disko.nix) already gates access at
  # boot, so a second password prompt here would just be redundant on top
  # of disk decryption.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "start-hyprland";
        user = username;
      };
      # Fallback if I ever log back out to a greeter (e.g. switching users).
      default_session = {
        command = "start-hyprland";
        user = username;
      };
    };
  };

  # Portals I need under Wayland: screen share, file pickers, etc.
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
  # `systemctl suspend`, not the power button, not the lid switch. This is
  # more reliable than editing hypridle.conf, since that would only cover
  # the idle-timeout path (and I don't even use hypridle in this setup —
  # see home.nix for why).
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
  # trash spec expects. I want that, plus this also brings network-mount
  # browsing (sftp://, smb://, ...) and drag-and-drop between apps that
  # expect gvfs, not just trash.
  services.gvfs.enable = true;

  # --- Thunar + archive plugin ---
  # Thunarx plugins (thunar-archive-plugin, which adds the right-click
  # Compress.../Extract Here entries) only get picked up if Thunar itself is
  # built with them via this module's `plugins` list — just adding the
  # plugin package to home.packages alongside a separately-installed Thunar
  # (as I used to do) doesn't work, since Thunar only scans THUNARX_DIRS
  # from its own wrapper, not an arbitrary sibling package in the profile.
  # xarchiver (home.nix) is the actual archive-manager backend the plugin
  # calls out to; zip/unzip/p7zip (home.nix) are the formats it can use.
  programs.thunar = {
    enable = true;
    plugins = [ pkgs.thunar-archive-plugin ];
  };

  # --- Gaming: see gaming.nix (Steam, gamescope, gamemode) ---

  # --- Flatpak ---
  services.flatpak.enable = true;
  # nix-flatpak's own auto-updater — registers a systemd timer that updates
  # my installed Flatpaks (Sober here) in place. Nix itself has nothing to
  # do with keeping Flatpak apps current; this is the one piece of "staying
  # updated" that isn't covered by bumping flake.lock. I run it daily
  # rather than weekly: Sober/Roblox ships new builds faster than once a
  # week, and Sober refuses to launch at all against a stale build until
  # it's updated.
  services.flatpak.update.auto = {
    enable = true;
    onCalendar = "daily";
  };
  # I also update on every boot, not just once a day — Sober/Roblox ships
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
    "org.vinegarhq.Sober" # Roblox client
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
    # my virtual mic (see audio-routing.nix).
    pavucontrol  # GUI mixer/volume control per app and device
    qpwgraph     # GUI PipeWire patchbay, for wiring virtual audio nodes together
  ];

  programs.nix-ld.enable = true;

  # --- Virtualisation: see windows-vm.nix (libvirtd, virt-manager, VM def) ---

  system.stateVersion = "26.11";
}
