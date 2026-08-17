{ config, pkgs, lib, inputs, username, userDescription, hostname, ... }:

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

  # greetd starts Hyprland straight for me, no tuigreet prompt and no
  # password check of its own — the auth step just moves to caelestia's own
  # lock screen at the very start of the session instead (see home.nix ->
  # caelestia/hypr-user.lua, which locks on hyprland.start).
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "start-hyprland";
        user = username;
      };
      # Fallback if I ever log back out to a greeter (e.g. switching users)
      default_session = {
        command = "start-hyprland";
        user = username;
      };
    };
  };

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
  # nix-flatpak's own auto-updater — registers a weekly systemd timer that
  # updates installed Flatpaks (Sober here) in place. Nix itself has
  # nothing to do with keeping Flatpak apps current; this is the one piece
  # of "staying updated" that isn't covered by bumping flake.lock.
  services.flatpak.update.auto = {
    enable = true;
    onCalendar = "weekly";
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
