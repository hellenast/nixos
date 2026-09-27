{ pkgs, inputs, ... }:

# The terminal: kitty, fish (with the caelestia dots' config), starship,
# fastfetch with a custom logo, and btop.
let
  dots = inputs.caelestia-dots-src;

  # Custom fastfetch logo — a horned, winged figure — instead of the NixOS
  # one.
  demonLogo = ''
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣤⠤⠤⢴⣿⣿⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠆
    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⡶⠟⡩⠟⠉⠀⠀⠀⣠⣿⣿⣿⡇⠀⠀⠙⣶⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⡿⠀
    ⠀⠀⠀⠀⠀⠀⠀⢀⣤⣀⣠⣤⣤⠖⢡⠊⣠⠎⠀⠀⠀⠀⣠⠞⣼⣿⣿⣿⠀⠀⠀⠀⠘⣿⡌⠳⣄⡀⠀⠀⠀⠀⠀⠀⣀⣼⣿⠃⠀
    ⠀⠀⠀⠀⢀⣠⠚⣡⠞⣿⣿⣿⠁⠀⢠⣾⠃⠀⠀⠀⠀⣰⠃⣰⣿⣷⣿⡏⠀⠀⠀⠀⠀⣿⣿⠀⢳⣉⢢⠀⠀⢀⣀⣼⣿⣿⠋⠀⠀
    ⠀⠀⠈⢉⣽⠁⢰⣿⢟⣿⡟⠀⠀⢀⣿⠏⠀⠀⠀⠀⣰⠁⣰⠋⠈⠊⢻⠇⠀⠀⠀⠀⠀⣿⣿⠐⢠⡋⣈⠴⣾⣿⣿⢿⡿⠃⠀⠀⠀
    ⠀⠀⢀⣾⡏⠀⣼⣿⣿⡼⠀⠀⠀⣸⡿⠀⠀⠀⠀⢰⠃⢠⠇⠀⠀⠀⡾⠀⠀⠀⠀⠀⢀⣿⡟⠀⢸⠏⠁⠀⠀⠻⣥⠞⠀⠀⠀⠀⠀
    ⠀⢀⡞⠁⠀⣸⠿⣿⣿⠇⡀⠀⠀⣿⡇⠀⠀⠀⠀⡟⢀⡏⠀⠀⣀⠜⣇⣠⣴⠂⠀⠀⣾⠟⠀⠀⡾⠀⠀⢀⣠⠾⠁⠀⠀⠀⠀⠀⠀
    ⠀⢸⠁⠀⢀⢿⣶⡇⣿⠀⣇⠀⠀⣿⡇⠀⠀⠀⠀⣿⣻⠒⠒⠛⠋⠉⣉⣩⠀⠀⣠⠞⢹⠉⢳⣴⠃⢶⠒⠉⢹⡄⠀⠀⠀⠀⠀⠀⠀
    ⠀⠁⠀⠀⣸⠀⠻⡇⢸⠀⠸⡄⠀⠻⣧⣄⡀⢀⣠⣿⣿⣿⠿⠿⠿⡷⣿⣏⣠⣾⠁⠀⠀⢠⡿⠋⠓⢼⡄⠀⢸⡇⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⣿⠀⢸⣇⠘⣧⠀⠱⡀⠀⣯⢻⠙⠓⢿⡟⠉⠀⠀⠐⢿⣿⣧⠉⢱⣇⣠⣴⢠⡿⣿⡷⣶⣼⣞⠁⣸⣇⠀⠀⠀⠀⠀⠀⠀
    ⠀⠄⠀⠀⡇⠀⠘⡿⣄⣻⣧⠀⠁⢠⠘⣎⣇⠀⡿⢷⣀⣀⣀⡯⠼⠿⠼⠇⠈⠁⠴⠛⢁⣀⣿⣿⡏⠻⣿⢤⣿⡿⠀⠀⠀⠀⠀⠀⠀
    ⠀⢠⠀⠀⡇⣠⠴⡿⠿⠷⠶⢵⢤⣈⣣⣈⣻⣦⣣⣠⠒⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⠟⠻⢧⣰⣏⣹⠟⠁⠀⠀⠀⠀⠀⠀⠀
    ⠀⠘⡄⠀⣷⠘⢾⡢⠀⢢⢦⠉⠉⢾⡏⠩⣄⣳⡈⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⣽⣿⡯⣷⡄⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⢻⠀⢹⡄⠀⢹⡦⣄⠻⣷⣀⡀⢳⠀⣇⠈⠉⠀⠀⠀⠀⠀⢀⣀⣠⣄⣀⡀⢰⣧⠀⠀⠀⠀⠀⠀⢸⣷⡿⡆⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⣼⠆⠸⡷⢄⢸⠀⡇⠳⣄⠀⣉⣻⣆⣻⠀⠀⠀⠀⠀⠀⠀⣾⣿⣦⣿⣷⣯⡿⠹⡦⣄⡀⠀⠀⠀⡼⢸⠀⣧⠀⠀⠀⠀⠀⠀⠀
    ⠀⢠⢿⠀⠀⣧⠈⡻⣴⠇⠀⣿⡗⠛⢾⣷⡟⠷⠄⠀⠀⠀⠀⠀⢧⠈⠙⠟⢿⣿⣿⡀⠘⢏⠀⠀⢀⣼⠁⢸⠀⢸⡄⠀⠀⠀⠀⠀⠀
    ⡰⣧⣾⠀⠀⣿⢰⣷⣹⠀⠀⢻⣧⣤⣾⣻⠙⣦⡀⠀⠀⠀⠀⠀⠈⠓⠤⣀⡀⣿⣀⠷⡀⠀⠳⣤⣿⡾⠒⢺⡀⠀⢷⠀⠀⠀⠀⠀⠀
    ⢅⠇⡟⠀⠀⣿⣼⠀⣿⡆⠀⠀⠈⢉⡏⡏⠀⢹⡈⠓⠆⠀⠀⠀⠀⠀⠀⠀⠉⠉⠁⠀⠙⣦⡜⢁⡞⠀⠀⡴⠳⣄⡌⠣⡀⠀⠀⠀⠀
    ⡞⢰⠇⠀⢰⣿⡇⢰⡿⠀⠀⠀⠀⣸⠀⣇⠀⣸⣷⣦⡀⠀⣤⣖⣶⣤⣤⣀⣀⣀⣀⣠⠚⢻⠁⢸⣀⣀⣸⣥⠴⠆⠀⠀⠹⡄⠀⠀⠀
    ⠁⣼⢠⢠⡏⡏⠁⣈⠿⠚⠋⠛⠒⢿⠀⠘⢾⣿⡟⠿⣿⣿⣿⣿⣿⣿⡗⣿⣿⣏⡏⢸⡆⠈⡿⠉⠉⢉⣤⡟⢶⠤⢄⠀⠀⠹⡄⠀⠀
    ⢀⡏⣿⣿⠀⣧⠞⠁⠀⠀⠀⠀⠀⠈⢧⡀⠀⠙⢳⡖⠀⠉⠡⣙⡿⠿⠋⠻⠟⠁⠉⠻⢿⣿⡁⠒⠲⡖⠋⠙⢟⢦⠀⠀⠀⠀⠘⣆⠀
    ⣼⠃⣿⣉⡼⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠋⢹⡇⠀⠀⠀⠀⠉⠢⠄⠀⠀⠀⠠⠒⠋⠉⢧⡀⠈⠀⠀⠀⠈⠻⢆⠀⠀⠀⠀⠘⣆
    ⠻⢇⢹⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠒⠿⠦⢤⣀⠀⠀⠀⠀⠙⠀⢀⣄⣀⣹
    ⠀⠈⠻⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⣿⣶⣤⣍⡙⠒⠦⢄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠲⣦⣤⣤⣶⣾⣿⣿⣿
  '';
in
{
  # Font and slight background transparency. kitty is deliberately not
  # tagged "+opaque" in Hyprland (as foot was in the dots): that tag makes
  # the compositor treat the window as fully opaque, which fights with
  # background_opacity. The dots' global 0.99 window opacity rule still
  # applies on top, as a barely visible fade; background_opacity is what
  # makes the background see-through while text stays fully opaque.
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      package = pkgs.nerd-fonts.jetbrains-mono;
    };
    settings = {
      background_opacity = "0.99";
    };
  };

  home.packages = with pkgs; [
    fish       # login shell (enabled system-wide in system/base.nix)
    starship   # shell prompt, started by the dots' fish config
    fastfetch  # system-info banner, run by the dots' fish greeting
    btop       # resource monitor, behind the sysmon scratchpad (home/caelestia.nix)
  ];

  # The dots' fish config.
  xdg.configFile."fish" = {
    source = "${dots}/fish";
    recursive = true;
  };

  # A custom config.jsonc replaces fastfetch's module list outright instead
  # of merging with it (a logo-only config shows an empty info panel), so
  # this repeats fastfetch's default modules, from `fastfetch --gen-config`.
  xdg.configFile."fastfetch/config.jsonc".text = builtins.toJSON {
    logo = {
      type = "data";
      source = demonLogo;
    };
    modules = [
      "title"
      "separator"
      "os"
      "host"
      "kernel"
      "uptime"
      "packages"
      "shell"
      "display"
      "de"
      "wm"
      "wmtheme"
      "theme"
      "icons"
      "font"
      "cursor"
      "terminal"
      "terminalfont"
      "cpu"
      "gpu"
      "memory"
      "swap"
      "disk"
      "localip"
      "battery"
      "poweradapter"
      "locale"
      "break"
      "colors"
    ];
  };
}
