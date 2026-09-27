{ pkgs, inputs, username, ... }:

let
  dots = inputs.caelestia-dots-src;

  # The dots' "Open Terminal Here" custom action, with `foot` swapped for
  # `kitty` (the terminal this setup uses).
  thunarUcaKitty = pkgs.writeText "uca.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <actions>
    <action>
    	<icon>utilities-terminal</icon>
    	<name>Open Terminal Here</name>
    	<submenu></submenu>
    	<unique-id>1710575157271461-1</unique-id>
    	<command>kitty -d %f</command>
    	<description>Open the current directory in kitty</description>
    	<range></range>
    	<patterns>*</patterns>
    	<startup-notify/>
    	<directories/>
    </action>
    </actions>
  '';
in
{
  # Thunar with the archive plugin (right-click Compress.../Extract Here).
  # Thunar only loads plugins from its own wrapper, so the plugin has to be
  # built in here — installing it next to Thunar as a separate package does
  # nothing.
  programs.thunar = {
    enable = true;
    plugins = [ pkgs.thunar-archive-plugin ];
  };

  # gvfs gives Thunar a trash:// backend. Without it, Delete permanently
  # deletes instead of moving to the trash. It also enables browsing
  # network locations (sftp://, smb://, ...).
  services.gvfs.enable = true;

  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # The archive manager the plugin drives. It only works with the few
      # managers it ships wrapper scripts for (ark, engrampa, file-roller);
      # anything else, e.g. xarchiver, fails with "No suitable archive
      # manager found". engrampa is the lightest of those.
      engrampa
      # The format tools engrampa uses.
      unzip  # extracts .zip
      zip    # creates .zip
      p7zip  # .7z and many other formats
    ];

    # The dots' Thunar config: custom actions and volume-manager settings.
    # Listed file by file (instead of linking ${dots}/thunar as a whole) so
    # uca.xml can be the kitty version above. Colours don't come from here:
    # caelestia themes Thunar at runtime through the GTK theme.
    xdg.configFile."Thunar/thunar-volman.xml".source = "${dots}/thunar/thunar-volman.xml";
    xdg.configFile."Thunar/uca.xml".source = thunarUcaKitty;
  };
}
