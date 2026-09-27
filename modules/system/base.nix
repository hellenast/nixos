{ pkgs, username, userDescription, hostname, timeZone, defaultLocale, consoleKeyMap, ... }:

# The basics every install of this config needs: machine identity, locale,
# the user account and a few CLI tools. All the values come from
# variables.nix.
{
  # --- Networking ---
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  # --- Time / locale ---
  time.timeZone = timeZone;
  i18n.defaultLocale = defaultLocale;

  # TTY keymap, matching the intl dead-key layout Hyprland uses
  # (home/hyprland.nix). Only affects plain virtual consoles.
  console.keyMap = consoleKeyMap;

  # --- User ---
  # More groups are added by the modules that need them (docker in
  # apps/dev.nix, libvirtd in virtualisation/windows-vm.nix). Group changes
  # only apply after logging out and back in.
  users.users.${username} = {
    isNormalUser = true;
    description = userDescription;
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
    shell = pkgs.fish;
  };
  # Needed system-wide for fish to work as a login shell (vendor
  # completions, /etc/shells entry). The user's fish config is in
  # home/terminal.nix.
  programs.fish.enable = true;

  environment.systemPackages = with pkgs; [
    git       # version control
    wget      # command-line downloader
    curl      # command-line HTTP client
    usbutils  # lsusb, for finding USB vendor/product ids (virtualisation/windows-vm.nix)
  ];

  # The NixOS release this machine was first installed with. Don't bump it
  # on upgrades — it only controls stateful defaults (database formats,
  # etc.), not which package versions are installed.
  system.stateVersion = "26.11";
}
