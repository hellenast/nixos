{ config, pkgs, lib, inputs, username, ... }:

let
  dots = inputs.caelestia-dots-src;

  # The VSCodium theme extension ships as a versioned .vsix inside the dots
  # repo, so I find it by suffix instead of hardcoding a version I'd have to
  # keep bumping by hand. Same for the extension's own install directory
  # name, which I need later to check whether it's already installed.
  vscodeIntegrationDir = "${dots}/vscode/caelestia-vscode-integration";
  vscodeIntegrationVsixName = lib.findFirst (n: lib.hasSuffix ".vsix" n) null (builtins.attrNames (builtins.readDir vscodeIntegrationDir));
  vscodeIntegrationVsix = "${vscodeIntegrationDir}/${vscodeIntegrationVsixName}";
  vscodeIntegrationExtensionDir = "soramanew.${lib.removeSuffix ".vsix" vscodeIntegrationVsixName}";

  # Custom fastfetch logo — a small horned/winged ASCII figure, swapped in
  # for the default NixOS pixel-art logo. fastfetch runs with no other
  # custom config (just its own built-in module list), so this only needs
  # to override "logo"; everything else stays default.
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

  # Initial content for ~/.config/caelestia/shell.json — see
  # seedCaelestiaShellConfig below for why this is seeded once instead of
  # symlinked in on every rebuild the way the module's own `settings` option
  # would do it.
  caelestiaShellSettings = {
    bar.status.showBattery = false;
    bar.scrollActions.brightness = false;
    osd.enableBrightness = false;
    # Both of these otherwise default to a locale-based guess (see
    # ServiceConfig in caelestia-shell's own C++ source) rather than a
    # fixed value — Celsius and 24-hour time regardless of locale.
    services.useFahrenheit = false;
    services.useTwelveHourClock = false;
  };
  caelestiaShellSettingsFile = pkgs.writeText "caelestia-shell-seed.json" (builtins.toJSON caelestiaShellSettings);

  # Thunar's "Open Terminal Here" action, vendored from the dots but with
  # `foot` swapped for `kitty` (see xdg.configFile."Thunar" below for why
  # this is listed as its own file instead of just pointing at
  # `${dots}/thunar` wholesale like the other vendored configs).
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

  # The dots' rules.lua tags "discord|equibop|vesktop" windows with
  # "+communication_app", and that tag's own rule assigns
  # `workspace = "special:communication"` (a special, screen-covering
  # workspace) — applied at window-creation time, before any later,
  # separately-loaded override rule gets a chance to affect it (confirmed
  # live: a "-communication_app" removal rule in hypr-user.lua did clear
  # the tag, per `hyprctl clients -j`, but the window still landed on the
  # special workspace regardless — the workspace decision had already been
  # made). So this has to be fixed at the source instead of overridden
  # after the fact.
  #
  # A more-specific xdg.configFile entry layered on top of the recursive
  # "hypr" source (the way thunarUcaKitty overrides just one file inside
  # the recursively-sourced Thunar dir) does NOT work here, confirmed by
  # building the actual home-manager generation and checking the result:
  # rules.lua still symlinked straight to the unpatched dots source — the
  # recursive directory's own per-file symlinking wins over a same-path
  # override, unlike Thunar's directory (which is sourced as two disjoint,
  # non-recursive per-file entries instead, so there's no overlap to lose).
  # So instead, this builds one patched copy of the whole hypr tree via
  # runCommand, and xdg.configFile."hypr" below sources *that* instead of
  # ${dots}/hypr directly — a single, unambiguous source, no overlapping
  # entries. The substitution itself is still a targeted string replace on
  # the live dots source (not a duplicated copy of the whole 200+ line
  # file), so it stays in sync with upstream changes to everything else in
  # rules.lua. The original array has "whatsapp" as its own separate
  # match entry, untouched by this — only "discord|equibop|vesktop" is
  # patched, so discord/equibop keep the scratchpad behavior as part of
  # that string, whatsapp keeps it too via its own untouched entry, and
  # vesktop alone is excluded.
  hyprDotsPatched = pkgs.runCommand "hypr-dots-patched" { } ''
    cp -r --no-preserve=mode ${dots}/hypr $out
    cp ${
      pkgs.writeText "rules.lua" (
        builtins.replaceStrings
          [ ''"discord|equibop|vesktop"'' ]
          [ ''"discord|equibop"'' ]
          (builtins.readFile "${dots}/hypr/hyprland/rules.lua")
      )
    } $out/hyprland/rules.lua
  '';
in
{
  imports = [
    inputs.caelestia-shell.homeManagerModules.default
    inputs.zen-browser.homeModules.beta
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.11";

  # --- Personal environment basics ---

  # Generates ~/.config/user-dirs.dirs (Pictures, Documents, Downloads, ...)
  # and creates the actual folders. I need this specifically because a few
  # apps (caelestia's wallpaper picker included) fall back to Qt/XDG's
  # standard Pictures location when nothing overrides it, and that lookup
  # silently breaks without this file existing at all.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    # Not a real freedesktop XDG dir, just a home-manager extra that
    # defaults on and creates ~/Projects on every activation otherwise.
    projects = null;
  };

  # Where I keep wallpapers, read by the `caelestia` CLI and the shell's
  # wallpaper picker. Both already default to this same path, but I set it
  # explicitly since it's the one thing every piece of this setup agrees on.
  home.sessionVariables.CAELESTIA_WALLPAPERS_DIR = "${config.home.homeDirectory}/Pictures/Wallpapers";

  # Cursor theme. Caelestia's own dots default to something called
  # "sweet-cursors" that isn't packaged in nixpkgs, so I went with Bibata
  # instead — modern, smooth scaling, still a normal arrow rather than a
  # stylised blob. This half covers GTK/X11/icon lookup; the native
  # Wayland/hyprcursor side is set again down in hypr-user.lua, because
  # greetd execs Hyprland directly instead of through a login shell, so I
  # can't rely on this alone reaching it in time.
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # caelestia recolors Papirus folder icons on every scheme change, but only
  # if it can find a *writable* copy — it never looks in the Nix store, and
  # couldn't edit it in place even if it did. This copies the theme out of
  # the store into ~/.local/share/icons once; after that I leave it alone so
  # papirus-folders' own edits stick around across rebuilds.
  home.activation.seedPapirusIcons = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.local/share/icons"
    if [ ! -d "$dest/Papirus" ]; then
      $DRY_RUN_CMD mkdir -p "$dest"
      for variant in Papirus Papirus-Dark Papirus-Light; do
        $DRY_RUN_CMD cp -r --no-preserve=mode "${pkgs.papirus-icon-theme}/share/icons/$variant" "$dest/$variant"
        $DRY_RUN_CMD chmod -R u+w "$dest/$variant"
      done
    fi
  '';

  # caelestia-shell's own settings GUI (the Nexus panel) writes changes
  # straight back to shell.json — it's meant to be a live, app-owned file,
  # not a static one. The module's own `settings` option manages shell.json
  # as an `xdg.configFile` symlink into the Nix store though, which is
  # read-only — so every rebuild (symlink gets reinstalled, shell reloads
  # it) and every GUI settings change both hit the same "tried to save a
  # read-only file" wall, which is exactly the "Failed to save config" toast
  # I kept seeing. Seeding it once (same pattern as seedPapirusIcons above)
  # instead of symlinking it in lets the shell actually own the file after
  # first boot — no more toast, and GUI toggles persist across reboots.
  # Trade-off: if I ever want to change caelestiaShellSettings above, this
  # won't pick it up on its own — I need to `rm ~/.config/caelestia/shell.json`
  # once so it reseeds.
  home.activation.seedCaelestiaShellConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.config/caelestia/shell.json"
    if [ ! -e "$dest" ]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "$dest")"
      $DRY_RUN_CMD cp --no-preserve=mode "${caelestiaShellSettingsFile}" "$dest"
      $DRY_RUN_CMD chmod u+w "$dest"
    fi
  '';

  # Vesktop (Electron) persists its own window state in state.json,
  # including `maximized`, and re-requests that state on every launch. On
  # Hyprland that request doesn't play well with tiling — it visually takes
  # over the screen instead of snapping into the layout like other tiled
  # windows. Vesktop rewrites this file on every close, re-setting
  # maximized:true if that's how it was left, so a one-time fix wouldn't
  # stick — this idempotently flips just that one field back on every
  # activation instead, leaving the rest of the file untouched.
  home.activation.unmaximizeVesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.config/vesktop/state.json"
    if [ -e "$dest" ]; then
      $DRY_RUN_CMD ${pkgs.jq}/bin/jq '.maximized = false' "$dest" > "$dest.tmp" \
        && $DRY_RUN_CMD mv "$dest.tmp" "$dest"
    fi
  '';

  # --- Spotify (Flatpak, user-scope) ---
  # I install Spotify here instead of as a normal package because spicetify
  # needs to patch its files in place, and neither the Nix store nor a
  # system-wide Flatpak install (root-owned /var/lib/flatpak) are writable
  # by me. A user-scope Flatpak install lands in ~/.local/share/flatpak,
  # which I do own. This module's install trigger doesn't depend on
  # graphical-session.target either (which never activates in my greetd
  # setup — see programs.caelestia.systemd.enable below for why that
  # matters), so it just runs on every `home-manager switch`.
  services.flatpak = {
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];
    packages = [ "com.spotify.Client" ];
    # A Flatpak update overwrites Spotify's files, silently undoing
    # spicetify's in-place patch until something re-applies it. That
    # already happens somewhat naturally — caelestia-spotify-resync.sh
    # (theme.postHook above) runs `spicetify apply` on every scheme
    # change, which most sessions trigger sooner or later — but it's not
    # instant. Worth remembering if Spotify looks unthemed right after an
    # update: change the wallpaper/scheme once, or just run `spicetify
    # apply` by hand.
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };

  # --- Caelestia shell + CLI ---
  # This is the actual desktop shell (bar, launcher, lock screen, wallpaper
  # picker, notifications...) plus the CLI that drives its dynamic theming.
  programs.caelestia = {
    enable = true;
    cli.enable = true;

    # The module wants to run the shell as a systemd --user service, wired
    # to graphical-session.target — but that target never activates here,
    # since greetd execs Hyprland directly with no uwsm/session-ceremony
    # step to flip it on. The shell only actually starts because the dots'
    # own hypr/hyprland/execs.lua launches it directly as a Hyprland child
    # (`caelestia shell -d`). So the systemd unit is dead weight, and worse:
    # anything I set via systemd.environment would never reach the real
    # process anyway. Disabled, and I set env vars through hl.env() in
    # hypr-user.lua below instead, since that's the path that's actually live.
    systemd.enable = false;

    # Deliberately NOT using this module's `settings` option for shell.json
    # — see seedCaelestiaShellConfig below for why. shell.json is seeded
    # from caelestiaShellSettings (defined in the `let` block up top)
    # instead.

    cli.settings = {
      theme = {
        enableTerm = true;
        enableHypr = true;
        enableDiscord = true;
        enableSpicetify = true;
        enableFuzzel = true;
        enableBtop = true;
        enableGtk = true;
        enableQt = true;
        enableZed = false;  # Zed isn't installed — nothing to theme
        iconTheme = "Papirus-Dark";
        iconThemeLight = "Papirus-Light";
        iconThemeDark = "Papirus-Dark";

        # Spotify can't do true live theme sync like everything else here —
        # spicetify's own "watch -s" mode always kills and relaunches
        # Spotify by exec'ing the raw binary at spotify_path directly, and
        # that crashes instantly outside the Flatpak sandbox it actually
        # needs to run in. This isn't a gap on my end; even the go-to
        # community fixer script for Spicetify-on-Flatpak never touches
        # `spicetify watch`, only the one-time `apply`. This hook just
        # re-patches Spotify with the current colors on every scheme change
        # (fast, and doesn't touch the running process at all) — I restart
        # Spotify myself when I want to see the new look, rather than have
        # it auto-launch/restart in the background, which was surprising me
        # by popping Spotify open on its own after a rebuild even when I
        # hadn't had it running. Backgrounded (trailing &) so it doesn't
        # block caelestia's own scheme-set command.
        postHook = "$HOME/.local/bin/caelestia-spotify-resync.sh &";
      };

      toggles = {
        # The dots' own functions.lua hardcodes `foot` as the terminal for
        # this Super+<sysmon key> floating-btop scratchpad. `command` here
        # overrides just that field on top of the dots' defaults (see
        # load_toggle_config()/merge() in the dots' functions.lua, which
        # reads exactly this cli.json path) — kitty replaces foot, with the
        # same --class/-T/fish -C invocation the dots used.
        sysmon = {
          btop = {
            command = [ "kitty" "--class" "btop" "-T" "btop" "fish" "-C" "exec btop" ];
          };
        };
        communication = {
          # Disabled: this made Super+D (and anything else wired to the
          # dots' "communication" toggle, e.g. a shell dashboard icon)
          # treat Vesktop as a scratchpad app — spawning or moving it onto
          # a special covering workspace (place_apps() in the dots'
          # functions.lua) instead of it just being a normal window. That's
          # what was overriding the "-communication_app" tag fix in
          # hypr-user.lua: the tag only stopped the static Hyprland
          # windowrule from placing it there, but this toggle system moves
          # matching windows explicitly, independent of tags. With this
          # off, Vesktop just opens and tiles normally, launched however
          # you'd launch any other app (app launcher, a taskbar entry,
          # etc.) — Super+D now simply has nothing configured to toggle.
          discord = {
            enable = false;
            match = [{ class = "vesktop"; }];
            command = [ "vesktop" ];
            move = true;
          };
        };
        music = {
          spotify = {
            enable = true;
            # "spotify" (lowercase) is the real window class the Flatpak
            # build reports. I kept "Spotify" too since caelestia's matcher
            # does substring containment rather than exact equality, so it
            # still catches titles like "Spotify Premium" fine.
            match = [{ class = "spotify"; } { initialTitle = "Spotify"; }];
            # Plain launch, no `spicetify watch` — see theme.postHook above
            # for how color sync actually happens instead.
            command = [ "flatpak" "run" "com.spotify.Client" ];
            move = true;
          };
        };
      };
    };
  };

  # --- Zen browser ---
  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;
  };

  # --- Kitty ---
  # Font + a bit of background transparency. Deliberately NOT tagging kitty
  # "+opaque" in hypr-user.lua below the way foot used to be (see the
  # terminal-switch comments there) — that tag forces the window to be
  # treated as fully opaque at the compositor level, which either cancels
  # out or visually conflicts with the client-side transparency
  # `background_opacity` renders here. The global 0.99 default opacity
  # rule from the dots (vars.windowOpacity, applied to all non-fullscreen
  # windows) still applies on top of this — a barely-noticeable additional
  # fade over the whole window, background_opacity is what actually
  # produces the see-through effect while keeping text fully legible.
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

  # --- Packages ---
  home.packages = with pkgs; [
    # Terminal + shell tooling the dots expect to be around.
    fish       # login shell
    starship   # shell prompt theme

    fastfetch  # the system-info banner shown on shell startup (custom logo, see above)
    btop       # interactive process/resource monitor, backs the sysmon scratchpad

    # Bibata cursor theme binary — wired up via home.pointerCursor above.
    bibata-cursors

    vscodium  # code editor

    bitwarden-desktop  # password manager desktop app

    # Discord client. Vencord's built in, so theming/plugins work without
    # extra setup beyond enabling the theme once in its own settings.
    vesktop

    # Drives the caelestia Spicetify theme. Spotify itself comes from
    # Flatpak (above), not nixpkgs, specifically so this has something
    # writable to patch.
    spicetify-cli

    # adw-gtk3 is the Adwaita-based GTK3 theme whose symbolic colours
    # (accent_color, window_bg_color, ...) caelestia's gtk.css template
    # overrides on every switch — without it there's nothing for that CSS
    # to actually restyle. papirus-folders is the tool that recolors the
    # Papirus folder icons (see seedPapirusIcons above for the setup that
    # makes it able to run at all).
    adw-gtk3
    papirus-folders

    # Archive support
    unzip          # extracts .zip
    zip            # creates .zip
    p7zip          # .7z and a bunch of other formats via 7z
    xarchiver      # lightweight GUI archive manager Thunar can call out to
    thunar-archive-plugin  # lets Thunar create/extract archives from its own right-click menu

    thunar  # file manager

    zapzap  # WhatsApp desktop client

    # Misc utilities the shell/CLI lean on directly
    playerctl       # media player control (play/pause/next), used by bar/OSD widgets
    brightnessctl   # backlight control, used by the brightness OSD
    grim            # takes the actual screenshot (screencopy)
    slurp           # interactive region selector, used by grim/grimblast for area captures
    grimblast  # freeze-then-select screenshots (hyprpicker under the hood)
    cliphist        # clipboard history, backing the clipboard-history picker
    wl-clipboard    # wl-copy/wl-paste, used to copy screenshots to the clipboard
    libnotify       # notify-send, used for screenshot/save notifications

    dart-sass            # compiles the live Discord theme CSS
    app2unit             # used by the CLI to launch toggled apps
    gpu-screen-recorder   # backs `caelestia record`
    papirus-icon-theme   # the icon theme itself (theme.iconTheme above)
  ];

  # --- Hyprland ---

  # The dots' own Hyprland config, dropped in wholesale — except rules.lua,
  # patched for the vesktop scratchpad fix (see hyprDotsPatched above).
  xdg.configFile."hypr" = {
    source = hyprDotsPatched;
    recursive = true;
  };

  # No hypridle.conf here on purpose: idle/lock/suspend isn't handled by
  # hypridle at all in this setup. caelestia-shell manages it natively
  # (modules/IdleMonitors.qml + its SessionManager service, listening to
  # logind directly for sleep/lock-requested events, driving the shell's own
  # lock screen). Nothing in the dots execs hypridle, so there's nothing to
  # override — idle timeouts/actions go through cli.settings (shell.json)
  # instead, if I ever want to tweak them.

  # My own overrides on top of the dots' Hyprland config. Caelestia reads
  # this specific file for exactly this purpose, so it survives `caelestia
  # update` overwriting the vendored dots above.
  #
  # NOTE: this is the newer Lua config format (Hyprland 0.55+). If a future
  # dots update reverts to the old hyprlang format, this whole block becomes:
  #   xdg.configFile."caelestia/hypr-user.conf".text = ''
  #     input {
  #         kb_layout  = us
  #         kb_variant = intl
  #     }
  #   '';
  xdg.configFile."caelestia/hypr-user.lua".text = ''
    hl.config({
      input = {
        kb_layout = "us",
        kb_variant = "intl",
      },
    })

    -- Cursor theme again, natively for Wayland/hyprcursor clients this time
    -- (home.pointerCursor above covers GTK/X11). Set explicitly because
    -- greetd execs Hyprland directly rather than through a login shell, so
    -- home-manager's session-vars script may not have run by the time this
    -- matters.
    hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
    hl.env("XCURSOR_SIZE", "24")

    -- Same reasoning, for the wallpaper folder var.
    hl.env("CAELESTIA_WALLPAPERS_DIR", os.getenv("HOME") .. "/Pictures/Wallpapers")

    -- USER_HOME: read by papirus-folders when caelestia shells out to
    -- `sudo -n papirus-folders` to recolor folders on scheme changes. That
    -- runs as root (sudo's default target, since caelestia never passes
    -- -u), which resets $HOME to /root — papirus-folders skips its own
    -- root-homedir lookup and uses this instead once it's set. The sudo
    -- side of this (env_keep, so root actually gets to see it) lives in
    -- caelestia-system.nix.
    hl.env("USER_HOME", os.getenv("HOME"))

    -- Monitor layout: DP-2 (2560x1440, main, on the left) at full 165Hz,
    -- HDMI-A-1 (2560x1080 ultrawide) to its right, matching my desk.
    -- Without this Hyprland re-picks its own defaults on every output
    -- re-enumeration (e.g. after lock/DPMS), which is why it kept
    -- reverting to 60Hz / swapping sides on me.
    hl.monitor({
      output = "DP-2",
      mode = "2560x1440@165",
      position = "0x0",
      scale = 1,
    })
    hl.monitor({
      output = "HDMI-A-1",
      mode = "2560x1080@60",
      position = "2560x0",
      scale = 1,
      transform = 3,
    })

    -- No more locking on session start here — tuigreet (configuration.nix)
    -- now handles auth at the actual entry point, before Hyprland even
    -- starts, so a second lock screen immediately after logging in would
    -- just be redundant.
    hl.on("hyprland.start", function()
      -- The dots' own execs.lua unconditionally runs
      -- `hyprctl setcursor sweet-cursors 24` in its own "hyprland.start"
      -- handler, which loads before this file — sweet-cursors isn't even
      -- installed, and no env var overrides a hardcoded call like that.
      -- Re-issuing it here (this file loads last) wins, since whichever
      -- `hyprctl setcursor` call runs last is what sticks. The sleep is
      -- slack against exec_cmd not being blocking.
      hl.exec_cmd("sleep 1 && hyprctl setcursor Bibata-Modern-Ice 24 "
        .. "&& gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Ice "
        .. "&& gsettings set org.gnome.desktop.interface cursor-size 24")
    end)

    -- The dots' own keybinds.lua binds Print (and Super+Shift+S /
    -- Super+Shift+Alt+S) to `caelestia screenshot`, which always stages a
    -- copy in ~/.cache/caelestia/screenshots first and only moves it to
    -- ~/Pictures/Screenshots if you click "Save" on the popup notification
    -- — otherwise it just sits in cache forever. Our own scripts below
    -- replace that entirely (freeze + region/full capture, straight to
    -- Pictures/Screenshots every time), so unbind the dots' defaults first.
    -- Must run before our own hl.bind("Print", ...) below: hl.unbind
    -- matches by key combo alone, with no notion of which bind owns it, so
    -- calling it after our own bind exists would remove ours too. This
    -- file loads after the dots' keybinds.lua (see the cursor-fix comment
    -- above), so at this point only the dots' bind exists yet to remove.
    hl.unbind("Print")
    hl.unbind("SUPER + SHIFT + S")
    hl.unbind("SUPER + SHIFT + ALT + S")

    -- Screenshots, popOS-style:
    --   Print         -> freeze screen, interactive region select
    --                     (grimblast --freeze, backed by hyprpicker),
    --                     opens in Drawing to annotate/crop before saving
    --   Shift + Print -> instant full-screen capture, saved + copied +
    --                     notified
    -- Scripts live below, installed into ~/.local/bin.
    hl.bind("Print", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/screenshot-region.sh"))
    hl.bind("SHIFT + Print", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/screenshot-full.sh"))

    -- Default terminal: kitty instead of the dots' default (foot). Same
    -- unbind-then-rebind pattern as the screenshot keys above — the dots'
    -- keybinds.lua already bound Super+T to `hl.dsp.exec_cmd(vars.terminal)`
    -- with "foot" baked into the dispatcher at bind-creation time, so
    -- mutating vars.terminal here wouldn't retroactively change it; has to
    -- be unbound and rebound instead.
    hl.unbind("SUPER + T")
    hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))

    -- Deliberately NOT tagging kitty "+opaque" here the way foot used to
    -- be — see the programs.kitty comment above for why that would
    -- conflict with kitty's own background transparency.

    -- Drawing floats only when opened for post-screenshot annotation, not
    -- when opened normally (double-clicking an image, launching it fresh,
    -- etc.) — a blanket class-based "+float" tag here would've floated
    -- every Drawing window, no way to distinguish the two from a static
    -- rule (both end up with the same class and, it turns out, the same
    -- generic "Drawing" window title regardless of which file is open, so
    -- title-matching doesn't work either). So this is scoped per-launch
    -- instead, directly in screenshot-region.sh below, via Hyprland's
    -- `[float] <cmd>` exec rule prefix — confirmed live that this floats
    -- only that one spawned window, not the class as a whole.

    -- Vesktop's exclusion from the "communication_app" special-workspace
    -- scratchpad group is handled at the source (a patched rules.lua, see
    -- hyprDotsPatched in the let block up top) rather than here — a
    -- "-tag" removal rule in this file, which loads after the
    -- dots' own rules.lua, turned out too late to affect it: the
    -- workspace assignment is resolved at window-creation time using the
    -- tag state as it existed at that point, not retroactively re-applied
    -- when a later rule changes the tag.
  '';

  # --- Helper scripts ---

  home.file.".local/bin/screenshot-full.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      mkdir -p "$HOME/Pictures/Screenshots"
      file="$HOME/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
      grimblast save screen "$file" >/dev/null
      wl-copy < "$file"
      notify-send -i "$file" "Screenshot saved" "$file"
    '';
  };

  home.file.".local/bin/screenshot-region.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      mkdir -p "$HOME/Pictures/Screenshots"
      file="$HOME/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
      # --freeze shows a static overlay of the current screen (via
      # hyprpicker) while slurp is up, so content can't shift/animate out
      # from under the selection mid-drag. Exits non-zero (killed by set -e)
      # if Escape cancels the selection, same as the old bare-slurp version.
      grimblast --freeze save area "$file" >/dev/null

      # Scopes floating to just this one spawned window (see the
      # hypr-user.lua comment on this) rather than tagging Drawing's whole
      # window class, so it still tiles normally when opened any other
      # way. Has to go through `hyprctl eval` calling exec_cmd's own
      # `rules` parameter for this — confirmed live that the classic
      # `hyprctl dispatch exec "[float] ..."` bracket-rule syntax doesn't
      # actually work under this Hyprland Lua-config version (silently
      # errors; an earlier test of mine that looked like it worked turned
      # out to be a stale leftover window from a different test, not
      # actually spawned by that command). exec_cmd is fire-and-forget
      # like dispatch was, so still need to wait for the window to
      # actually start, then wait for it to exit, before copying/notifying.
      hyprctl eval "hl.dispatch(hl.dsp.exec_cmd('drawing $file', { float = true }))"
      for _ in $(seq 1 50); do
        pgrep -f "$file" >/dev/null 2>&1 && break
        sleep 0.1
      done
      while pgrep -f "$file" >/dev/null 2>&1; do
        sleep 0.5
      done

      [ -f "$file" ] && wl-copy < "$file" && notify-send -i "$file" "Screenshot saved" "$file"
    '';
  };

  # Refreshes flake.lock (nixpkgs, home-manager, caelestia-shell/cli,
  # zen-browser, nixvirt, ...) — the Nix-side equivalent of "check for
  # updates" for everything that isn't a Flatpak (those auto-update on
  # their own timer, see services.flatpak.update.auto above and in
  # configuration.nix). Deliberately doesn't rebuild/deploy itself — a bad
  # nixpkgs bump is the kind of thing worth reviewing before committing to,
  # and the actual deploy needs an interactive sudo password anyway (same
  # reasoning as everywhere else in this config: I run that step myself).
  home.file.".local/bin/update-flake.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      cd "$HOME/nixos"

      echo "Updating flake inputs..."
      nix flake update

      if [ -d .git ]; then
        echo
        echo "=== flake.lock changes ==="
        git --no-pager diff -- flake.lock || true
      fi

      echo
      echo "Review the changes above, then deploy with:"
      echo "  sudo cp ~/nixos/*.nix /etc/nixos/ && sudo nixos-rebuild switch --flake .#"
    '';
  };

  # Bound to cli.settings.theme.postHook above. Just re-patches Spotify with
  # the freshly-generated colors — deliberately doesn't touch the running
  # process (no kill, no launch), since auto-restarting was popping Spotify
  # open on its own even when I didn't have it running. I restart it myself
  # when I want the new look. Lock-guarded (atomic mkdir, not a touch+test —
  # I hit a real race with the naive version) so a fast light/dark toggle or
  # a dynamic-scheme wallpaper slideshow can't pile up overlapping applies.
  home.file.".local/bin/caelestia-spotify-resync.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -uo pipefail

      lock="''${XDG_RUNTIME_DIR:-/tmp}/caelestia-spotify-resync.lock"
      mkdir "$lock" 2>/dev/null || exit 0
      trap 'rmdir "$lock"' EXIT

      spicetify apply >/dev/null 2>&1
    '';
  };

  # Any custom config.jsonc replaces fastfetch's module list outright
  # rather than merging with its built-ins (confirmed by building this and
  # running it for real: a logo-only config left the whole info panel
  # blank) — so the module list below is fastfetch's own default set,
  # copied from `fastfetch --gen-config`, kept alongside the logo override
  # purely to preserve the normal output.
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

  # --- Per-app config, vendored from caelestia-dots ---

  xdg.configFile."fish" = {
    source = "${dots}/fish";
    recursive = true;
  };

  # The actual "caelestia" Spotify theme spicetify applies.
  xdg.configFile."spicetify/Themes/caelestia" = {
    source = "${dots}/spicetify/Themes/caelestia";
    recursive = true;
  };

  # Thunar integration: custom actions (e.g. "Open Terminal Here") and
  # volume-manager config. Colour theming itself (thunar.css) is applied
  # separately at runtime by `caelestia` via ~/.config/gtk-3.0 and gtk-4.0 —
  # adw-gtk3 above is what actually renders it correctly.
  #
  # Split into two entries instead of pointing at `${dots}/thunar` wholesale
  # (like the other vendored configs) because uca.xml needs the `foot` ->
  # `kitty` swap — thunar-volman.xml is untouched, straight from the dots.
  xdg.configFile."Thunar/thunar-volman.xml".source = "${dots}/thunar/thunar-volman.xml";
  xdg.configFile."Thunar/uca.xml".source = thunarUcaKitty;

  # VSCodium is different from everything else here: theming isn't driven by
  # the `caelestia` CLI at all, it's the bundled caelestia-vscode-integration
  # extension (installed below) watching
  # ~/.local/state/caelestia/scheme.json itself and rewriting its own theme
  # file live. settings.json already sets workbench.colorTheme to
  # "Caelestia", so there's no manual theme picking needed once the
  # extension's in.
  xdg.configFile."VSCodium/User/settings.json".source = "${dots}/vscode/settings.json";
  xdg.configFile."VSCodium/User/keybindings.json".source = "${dots}/vscode/keybindings.json";
  xdg.configFile."codium-flags.conf".source = "${dots}/vscode/flags.conf";

  # Only install the extension if it's not already there. `codium
  # --install-extension` from a local .vsix always force-reinstalls
  # (overwrites the whole extension directory), which was wiping out
  # themes/caelestia.json — the file the extension itself regenerates at
  # runtime — on every single rebuild. That's why VSCodium used to only show
  # the right colors on the *second* launch: the first window had already
  # rendered before the extension's activate() got around to rewriting the
  # just-reset file. Skipping reinstall once it's present means that live
  # file actually survives across rebuilds.
  home.activation.caelestiaVscodeIntegration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.vscode-oss/extensions/${vscodeIntegrationExtensionDir}" ]; then
      $DRY_RUN_CMD ${pkgs.vscodium}/bin/codium $VERBOSE_ARG --install-extension "${vscodeIntegrationVsix}" || true
    fi
  '';

  # --- Compose key override ---
  # ' + c makes ç instead of the intl variant's default ć. `include "%L"`
  # keeps every other locale sequence (á, ã, ü, ...) and this just overrides
  # the one combo I actually want. Read by libxkbcommon regardless of
  # X11/Wayland, no separate service needed.
  home.file.".XCompose".text = ''
    include "%L"

    <dead_acute> <c> : "ç" U00E7
    <dead_acute> <C> : "Ç" U00C7
  '';

  # --- Known gap: Zen browser theming ---
  # dots/zen ships userChrome/userContent files, but they're dead weight —
  # Zen theming doesn't actually work upstream (manifest.toml says so
  # itself, and there's no apply_zen anywhere in the CLI), so I'm not wiring
  # any of it up.

  # --- Known gap: dead-key compose in Electron apps ---
  # ~/.XCompose above (and its ' + c -> ç override) works correctly in
  # anything that reads compose sequences via libxkbcommon — terminals, Qt
  # apps, GTK apps with no other IM active. Confirmed live that Electron
  # apps (VSCodium, Vesktop, Spotify's shell) don't: they ship their own
  # compose table baked in at build time from the standard locale data, so
  # ' + c gives the same ć the system default would, no matter what
  # ~/.XCompose says. Not fixable from this config — would need an actual
  # input-method daemon (ibus/fcitx) that Electron consults instead, which
  # is a bigger change for one app's dead keys and not guaranteed to honor
  # the override anyway.
}
