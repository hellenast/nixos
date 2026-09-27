{ lib, pkgs, username, userDescription, hostname, timeZone, defaultLocale, consoleKeyMap, ... }:

# The basics every install of this config needs: machine identity, locale,
# the user account and a few CLI tools. All the values come from
# variables.nix and the machine's hosts/<name>/variables.nix.
{
  # --- Networking ---
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  # --- Time / locale ---
  time.timeZone = timeZone;
  i18n.defaultLocale = defaultLocale;

  # TTY keymap, matching the layout Hyprland uses (home/hyprland.nix). Only
  # affects plain virtual consoles.
  console.keyMap = consoleKeyMap;

  # The LUKS passphrase is typed in the initrd, before that keymap normally
  # loads, so the kernel's built-in US layout reads it. With a non-US
  # keyboard (the laptops' ABNT2), the keymap is loaded there too, so the
  # passphrase is typed the way the keys say; fresh-install.sh switches the
  # live ISO to the same keymap before disko asks for it. US-based keymaps
  # (the desktop's us-acentos) are left out: the built-in US map types the
  # same characters, without dead keys getting in the way of a passphrase.
  console.earlySetup = !(consoleKeyMap == "us" || lib.hasPrefix "us-" consoleKeyMap);

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
