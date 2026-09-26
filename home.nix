{ config, pkgs, lib, inputs, username, keyboardLayout, keyboardVariant, primaryMonitor, secondaryMonitor, cursorTheme, cursorSize, ... }:

let
  dots = inputs.caelestia-dots-src;

  # The VSCodium theme extension ships as a versioned .vsix file inside the
  # dots repo, so I find it by suffix instead of hardcoding a version I'd
  # have to keep bumping by hand. Same for the extension's own install
  # directory name, which I need later to check whether it's already
  # installed.
  vscodeIntegrationDir = "${dots}/vscode/caelestia-vscode-integration";
  vscodeIntegrationVsixName = lib.findFirst (n: lib.hasSuffix ".vsix" n) null (builtins.attrNames (builtins.readDir vscodeIntegrationDir));
  vscodeIntegrationVsix = "${vscodeIntegrationDir}/${vscodeIntegrationVsixName}";
  vscodeIntegrationExtensionDir = "soramanew.${lib.removeSuffix ".vsix" vscodeIntegrationVsixName}";

  # Regenerates the extension's themes/caelestia.json from the current scheme
  # with the extension's own generator (out/theme.js) — exactly what its
  # activate() does, just earlier. The extension only rewrites that file
  # once VSCodium has finished starting, after the window was already
  # painted from the previous file, so every launch after a scheme change
  # showed the old colours until the next restart. Run before launch (the
  # codium wrapper below) and on every scheme change (postHook), the file
  # is already current when VSCodium reads it.
  vscodeThemeSync = pkgs.writeShellScript "caelestia-vscode-theme-sync" ''
    ext="$HOME/.vscode-oss/extensions/${vscodeIntegrationExtensionDir}"
    scheme="''${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/scheme.json"
    [ -f "$ext/out/theme.js" ] && [ -f "$scheme" ] || exit 0
    ${pkgs.nodejs}/bin/node -e '
      const fs = require("fs"), path = require("path");
      const [ext, schemePath] = process.argv.slice(1);
      const mod = require(path.join(ext, "out", "theme.js"));
      const scheme = JSON.parse(fs.readFileSync(schemePath, "utf8"));
      const colours = Object.fromEntries(Object.entries(scheme.colours).map(([n, c]) => [n, "#" + c]));
      const out = JSON.stringify((mod.default || mod)(colours));
      const file = path.join(ext, "themes", "caelestia.json");
      // Only write on change: the theme file is watched while VSCodium runs.
      if (!fs.existsSync(file) || fs.readFileSync(file, "utf8") !== out) fs.writeFileSync(file, out);
    ' "$ext" "$scheme" || true
  '';

  # VSCodium with the theme synced right before every launch (its .desktop
  # entry runs plain `codium`, so this covers launcher starts too).
  vscodiumCaelestia = pkgs.symlinkJoin {
    name = "vscodium-caelestia";
    paths = [ pkgs.vscodium ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = "wrapProgram $out/bin/codium --run ${vscodeThemeSync}";
  };

  # My custom fastfetch logo — a small horned/winged ASCII figure, swapped
  # in for the default NixOS pixel-art logo. I run fastfetch with no other
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
  # seedCaelestiaShellConfig below for why I seed this once instead of
  # symlinking it in on every rebuild the way the module's own `settings`
  # option would do it.
  caelestiaShellSettings = {
    bar.scrollActions.brightness = false;
    # bar.status.showBattery used to be the way to hide the battery icon,
    # but caelestia-shell's C++ config schema (plugin/src/Caelestia/Config/
    # barconfig.hpp) replaced that whole `status` object with a
    # `statusIcons` list of {id, enabled} entries instead — an unrecognised
    # `bar.status` key was exactly the "unknown config" notification I kept
    # seeing. ConfigList reloads replace the entire list wholesale rather
    # than merging by id, so every default entry has to be spelled out here
    # even though only `battery` differs from its default.
    bar.statusIcons = [
      { id = "lockStatus"; enabled = true; }
      { id = "audio"; enabled = true; }
      { id = "microphone"; enabled = false; }
      { id = "kbLayout"; enabled = false; }
      { id = "network"; enabled = true; }
      { id = "bluetooth"; enabled = true; }
      { id = "battery"; enabled = false; }
    ];
    # Same {id, enabled} list shape as statusIcons above, this time for
    # which modules show in the bar at all — full default list spelled out
    # for the same reload-replaces-wholesale reason.
    bar.entries = [
      { id = "logo"; enabled = true; }
      { id = "workspaces"; enabled = true; }
      { id = "spacer"; enabled = true; }
      { id = "activeWindow"; enabled = true; }
      { id = "spacer"; enabled = true; }
      { id = "tray"; enabled = true; }
      { id = "clock"; enabled = true; }
      { id = "statusIcons"; enabled = true; }
      { id = "power"; enabled = true; }
    ];
    osd.enableBrightness = false;
    # Both of these otherwise default to a locale-based guess (see
    # ServiceConfig in caelestia-shell's own C++ source) rather than a
    # fixed value — I want Celsius and 24-hour time regardless of locale.
    services.useFahrenheit = false;
    services.useTwelveHourClock = false;
  };
  caelestiaShellSettingsFile = pkgs.writeText "caelestia-shell-seed.json" (builtins.toJSON caelestiaShellSettings);

  # Thunar's "Open Terminal Here" action, vendored from the dots but with
  # `foot` swapped for `kitty` (see xdg.configFile."Thunar" below for why I
  # list this as its own file instead of just pointing at `${dots}/thunar`
  # wholesale like the other vendored configs).
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
  # separately-loaded override rule gets a chance to affect it. I confirmed
  # this live: a "-communication_app" removal rule in hypr-user.lua did
  # clear the tag, per `hyprctl clients -j`, but the window still landed on
  # the special workspace regardless — the workspace decision had already
  # been made. So I have to fix this at the source instead of overriding it
  # after the fact.
  #
  # A more-specific xdg.configFile entry layered on top of the recursive
  # "hypr" source (the way thunarUcaKitty overrides just one file inside
  # the recursively-sourced Thunar dir) does NOT work here — I confirmed
  # this by building the actual home-manager generation and checking the
  # result: rules.lua was still symlinked straight to the unpatched dots
  # source. The recursive directory's own per-file symlinking wins over a
  # same-path override, unlike Thunar's directory (which I source as two
  # disjoint, non-recursive per-file entries instead, so there's no overlap
  # to lose). So instead, this builds one patched copy of the whole hypr
  # tree via runCommand, and xdg.configFile."hypr" below sources *that*
  # instead of ${dots}/hypr directly — a single, unambiguous source, no
  # overlapping entries. The substitution itself is still a targeted
  # string replace on the live dots source (not a duplicated copy of the
  # whole 200+ line file), so it stays in sync with upstream changes to
  # everything else in rules.lua. The original array has "whatsapp" as its
  # own separate match entry, untouched by this — only
  # "discord|equibop|vesktop" is patched, so discord/equibop keep the
  # scratchpad behavior as part of that string, whatsapp keeps it too via
  # its own untouched entry, and vesktop alone is excluded.
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

  # CaelestiaZen — a community Sine mod (not part of the official dots) that
  # live-themes Zen from the current caelestia scheme. The official route,
  # the CaelestiaFox extension + native host in the dots' firefox/ dir,
  # pushes colours through Firefox's theme API, which Zen mostly ignores —
  # upstream marks Zen theming as won't-fix (manifest.toml, and
  # caelestia-dots/caelestia#148 and #424). CaelestiaZen sidesteps that: a
  # caelestia CLI user template (installed below) renders the scheme into a
  # CSS file on every scheme change, and the mod's chrome script injects that
  # file straight into Zen's UI, re-reading it whenever it changes — so it
  # hot-reloads like everything else here. Pinned by rev + hash instead of
  # as a flake input on purpose: it runs with full browser privileges, and my
  # deploy command only copies *.nix into /etc/nixos (not flake.lock), so a
  # new flake input would get locked to whatever upstream's HEAD happens to
  # be at deploy time rather than the commit I actually read through.
  # Bumping it means editing rev/hash by hand, after reading the new
  # theme-sync.uc.js.
  caelestiaZen = pkgs.fetchFromGitHub {
    owner = "dim-ghub";
    repo = "CaelestiaZen";
    rev = "aeb0cc00ef5a64e572abb02f94e672a651e5c2f3";
    hash = "sha256-q4BPInmlJ8vRxwJShYZ9OnBDDLNg7+Qz2Jrh/4i54E4=";
  };

  # The profile directory Zen created on its own first launch (random prefix
  # + profile name). Declaring the profile in programs.zen-browser below
  # makes home-manager own ~/.config/zen/profiles.ini, so this has to match
  # the existing directory exactly — anything else would point Zen at a
  # brand-new empty profile (the old one would still be on disk, just no
  # longer the one in use). On a fresh install home-manager creates this same
  # directory name itself, so nothing here is tied to this one machine.
  zenProfilePath = "kn7ftk1l.Default Profile";
  zenProfileDir = "${config.xdg.configHome}/zen/${zenProfilePath}";

  # A plain Python interpreter that can import the caelestia CLI's own
  # modules — the CLI's site-packages plus its Python dependencies, the same
  # set its own wrapper loads — so renderCaelestiaTemplates below can render
  # my user templates through the CLI's real code path.
  caelestiaCliPython = let
    cli = config.programs.caelestia.cli.package;
    python = lib.findFirst (p: (p.pname or "") == "python3") pkgs.python3 cli.propagatedBuildInputs;
    modules = python.pkgs.requiredPythonModules (builtins.filter (p: p ? pythonModule) cli.propagatedBuildInputs);
  in pkgs.writeShellScript "caelestia-cli-python" ''
    export PYTHONPATH=${lib.makeSearchPath python.sitePackages ([ cli ] ++ modules)}
    exec ${python.interpreter} "$@"
  '';

  # Material, the Millennium theme for Steam (Millennium itself is in
  # gaming.nix), pinned by rev + hash like CaelestiaZen and for the same
  # reason: it runs JavaScript inside the Steam client. Its "Matugen" colour
  # option re-fetches css/main/colors/matugen.css every 1.5s and applies it
  # live, so that one file is swapped for a symlink to the copy the caelestia
  # CLI renders from steamMaterialTemplate below — Steam then follows scheme
  # changes without a restart, same as Zen.
  steamMaterialTheme = pkgs.runCommand "steam-material-theme-caelestia" { } ''
    cp -r --no-preserve=mode ${pkgs.fetchFromGitHub {
      owner = "kuska1";
      repo = "Material-Theme";
      rev = "f91b4e9cbc5436f149e6b293391a9a96ab47fbe9";
      hash = "sha256-qPzo59NyKsmKkhupOf3n9X29p/Wbv7jaKDGaM23HTJo=";
    }} $out
    ln -sf ${config.xdg.stateHome}/caelestia/theme/steam-material.css $out/css/main/colors/matugen.css
  '';

  # Every --md-sys-color-* variable the Material theme reads, named the way
  # caelestia's scheme names them (camelCase — the template below converts
  # to the theme's kebab-case). Its own matugen.css uses full `rgb(...)`
  # values, which is exactly what the CLI's `.rgb` gives.
  steamMaterialColours = [
    "background" "error" "errorContainer" "inverseOnSurface" "inversePrimary" "inverseSurface"
    "onBackground" "onError" "onErrorContainer" "onPrimary" "onPrimaryContainer" "onPrimaryFixed"
    "onPrimaryFixedVariant" "onSecondary" "onSecondaryContainer" "onSecondaryFixed"
    "onSecondaryFixedVariant" "onSurface" "onSurfaceVariant" "onTertiary" "onTertiaryContainer"
    "onTertiaryFixed" "onTertiaryFixedVariant" "outline" "outlineVariant" "primary"
    "primaryContainer" "primaryFixed" "primaryFixedDim" "scrim" "secondary" "secondaryContainer"
    "secondaryFixed" "secondaryFixedDim" "shadow" "surface" "surfaceBright" "surfaceContainer"
    "surfaceContainerHigh" "surfaceContainerHighest" "surfaceContainerLow" "surfaceContainerLowest"
    "surfaceDim" "surfaceTint" "surfaceVariant" "tertiary" "tertiaryContainer" "tertiaryFixed"
    "tertiaryFixedDim"
  ];
  steamMaterialTemplate = let
    kebab = name: lib.concatMapStrings (c: if c != lib.toLower c then "-${lib.toLower c}" else c) (lib.stringToCharacters name);
  in ''
    /* Rendered by the caelestia CLI on every scheme change — see
       steamMaterialTheme in ~/nixos/home.nix. */
    :root {
      --theme-color: "Matugen";
      /* The theme hue-rotates a few of its images by this; its built-in
         colour presets all sit at roughly (preset hue - 215deg). */
      --hue-rotate: calc({{ primary.hue }}deg - 215deg);
      --md-sys-color-source-color: {{ primary_paletteKeyColor.rgb }};
    ${lib.concatMapStrings (n: "  --md-sys-color-${kebab n}: {{ ${n}.rgb }};\n") steamMaterialColours}}

    /* Light/dark follows the scheme too, overriding the theme's own
       Appearance option: the same variables its appearance/{dark,light}.css
       set, with the doubled :root winning on specificity whichever order
       Millennium injects the two in. --ON/--OFF are the theme's own
       space-toggle values, picked per mode through --caelestia-*-if-<mode>. */
    :root:root {
      color-scheme: only {{ mode }} !important;
      --scheme: {{ mode }};
      --caelestia-light-if-light: var(--ON);
      --caelestia-light-if-dark: var(--OFF);
      --caelestia-dark-if-light: var(--OFF);
      --caelestia-dark-if-dark: var(--ON);
      --scheme-light: var(--caelestia-light-if-{{ mode }});
      --scheme-dark: var(--caelestia-dark-if-{{ mode }});
      --caelestia-colour-if-light: white;
      --caelestia-colour-if-dark: black;
      --scheme-color: var(--caelestia-colour-if-{{ mode }});
      --caelestia-inverse-if-light: black;
      --caelestia-inverse-if-dark: white;
      --scheme-color-inverse: var(--caelestia-inverse-if-{{ mode }});
    }
  '';

  # Helium's generated Chrome theme (see the Helium section for why a theme
  # rather than caelestia's colour policy). Chrome wants [r, g, b] arrays,
  # hence the CLI's .red/.green/.blue. The version is built from a few
  # colours so a scheme change reads as a theme update to Chrome.
  heliumThemeDir = "${config.xdg.stateHome}/caelestia/helium-theme";
  heliumThemeTemplate = let
    rgb = c: "[{{ ${c}.red }}, {{ ${c}.green }}, {{ ${c}.blue }}]";
    # Chrome theme slot -> caelestia scheme colour. Same layering as
    # caelestia's own surfaces: frame darkest-but-one, toolbar/omnibox a
    # step up each, the new tab page the base surface.
    slots = {
      frame = "surfaceContainer";
      frame_inactive = "surfaceContainer";
      frame_incognito = "surfaceContainer";
      frame_incognito_inactive = "surfaceContainer";
      toolbar = "surfaceContainerHigh";
      toolbar_text = "onSurface";
      toolbar_button_icon = "onSurfaceVariant";
      tab_text = "onSurface";
      tab_background_text = "onSurfaceVariant";
      tab_background_text_inactive = "onSurfaceVariant";
      bookmark_text = "onSurface";
      omnibox_background = "surfaceContainerHighest";
      omnibox_text = "onSurface";
      button_background = "surfaceContainerHighest";
      ntp_background = "surface";
      ntp_text = "onSurface";
      ntp_link = "primary";
      ntp_header = "primary";
    };
  in ''
    {
      "manifest_version": 3,
      "name": "Caelestia",
      "description": "Generated by the caelestia CLI from the current scheme.",
      "version": "{{ surfaceContainer.hue }}.{{ surfaceContainer.lightness }}.{{ primary.hue }}.{{ primary.lightness }}",
      "theme": {
        "colors": {
          ${lib.concatStringsSep ",\n      " (lib.mapAttrsToList (slot: c: ''"${slot}": ${rgb c}'') slots)}
        }
      }
    }
  '';

  # ZapZap's WhatsApp Web CSS. WhatsApp colours its UI through its design
  # system's --WDS-* custom properties (each with -RGB/-rgb "r, g, b"
  # twins, for rgba() use) plus a few older --name/--name-rgb pairs; the
  # variable list and selectors follow Catppuccin's maintained WhatsApp Web
  # userstyle (catppuccin/userstyles, styles/whatsapp-web). Mapped onto
  # caelestia's Material roles rather than the scheme's Catppuccin-named
  # keys: in dark dynamic schemes those collapse (base/mantle/crust are all
  # near-black, and overlay2 — Catppuccin's secondary-text colour — too), so
  # secondary text would vanish. Translucent ones use rgb(... / alpha) with
  # the base colour's triplet, same as the userstyle's fade().
  zapzapTemplate = let
    triplet = c: "{{ ${c}.red }}, {{ ${c}.green }}, {{ ${c}.blue }}";
    wdsSolid = {
      accent = "primary";
      accent-emphasized = "primaryFixed";
      secondary-negative = "error";
      secondary-negative-emphasized = "error";
      secondary-positive = "success";
      secondary-warning = "yellow";
      content-default = "onSurface";
      content-deemphasized = "onSurfaceVariant";
      content-on-accent = "onPrimary";
      content-action-default = "primary";
      content-action-emphasized = "primaryFixed";
      content-external-link = "blue";
      content-inverse = "surface";
      content-read = "blue";
      background-wash-inset = "surface";
      background-wash-plain = "surface";
      background-elevated-wash-plain = "surface";
      background-elevated-wash-inset = "surface";
      modal-backdrop-solid = "surface";
      surface-default = "surfaceContainerLow";
      surface-emphasized = "surfaceContainer";
      surface-elevated-default = "surfaceContainer";
      surface-elevated-emphasized = "surfaceContainerHighest";
      surface-inverse = "onSurface";
      lines-outline-default = "outlineVariant";
      persistent-always-branded = "primary";
      systems-bubble-surface-incoming = "surfaceContainerHigh";
      systems-bubble-surface-outgoing = "secondaryContainer";
      systems-bubble-surface-overlay = "surfaceContainerLow";
      systems-bubble-surface-system = "surfaceContainerLow";
      systems-bubble-surface-e2e = "surfaceContainerHigh";
      systems-bubble-content-e2e = "yellow";
      systems-bubble-surface-business = "surfaceContainerHigh";
      systems-chat-surface-composer = "surfaceContainer";
      systems-chat-background-wallpaper = "surface";
      systems-chat-foreground-wallpaper = "surfaceContainerLow";
      systems-chat-surface-tray = "surfaceContainer";
      components-surface-nav-bar = "surfaceContainer";
      app-wash = "surfaceContainerHigh";
      white = "surface";
    };
    wdsFaded = {
      accent-deemphasized = [ "primary" "0.3" ];
      secondary-negative-deemphasized = [ "error" "0.3" ];
      secondary-positive-deemphasized = [ "success" "0.3" ];
      secondary-warning-deemphasized = [ "yellow" "0.3" ];
      content-disabled = [ "onSurface" "0.5" ];
      background-dimmer = [ "scrim" "0.3" ];
      surface-highlight = [ "onSurface" "0.2" ];
      surface-pressed = [ "onSurface" "0.2" ];
      lines-divider = [ "onSurface" "0.1" ];
      lines-outline-deemphasized = [ "onSurface" "0.3" ];
      persistent-activity-indicator = [ "success" "0.9" ];
      systems-bubble-content-deemphasized = [ "onSurface" "0.5" ];
      systems-status-seen = [ "onSurface" "0.5" ];
      components-platform-gesture-bar = [ "surface" "0.5" ];
      components-platform-status-bar = [ "surface" "0.8" ];
    };
    plainSolid = {
      white = "surface";
      attachment-type-stickers-color = "green";
      attachment-type-polls-color = "yellow";
      attachment-type-contacts-color = "sky";
      attachment-type-camera-color = "pink";
      attachment-type-photos-color = "blue";
      attachment-type-documents-color = "mauve";
      attachment-type-audio-color = "peach";
      attachment-type-event-color = "pink";
      toast-background = "surfaceContainerHighest";
      toast-text = "onSurface";
      picker-background = "surfaceContainerHighest";
      butterbar-blue-nux-background = "sky";
      blue-light = "blue";
      gray-500 = "onSurfaceVariant";
      focus-animation = "primaryContainer";
      focus-animation-deeper = "secondaryContainer";
      startup-icon = "surfaceContainerHighest";
      startup-background = "surface";
      progress-background = "surfaceContainerHigh";
      date-picker-text-color = "onSurface";
    };
    splash = {
      splashscreen-startup-background = "surface";
      splashscreen-startup-icon = "surfaceContainerHigh";
      splashscreen-primary-title = "onSurface";
      splashscreen-progress-primary = "primary";
      splashscreen-progress-background = "surfaceContainerHighest";
      splashscreen-secondary-lighter = "onSurfaceVariant";
      startup-icon = "surfaceContainerHighest";
      startup-background = "surface";
    };
    lines = f: set: lib.concatStrings (lib.mapAttrsToList f set);
  in ''
    /* Rendered by the caelestia CLI on every scheme change — see
       zapzapTemplate in ~/nixos/home.nix. The #whatsapp-web ones (the id on
       WhatsApp's <html>) come first because WhatsApp defines these
       variables on <html> through doubled atomic classes (.x.x:root) that
       outrank every class-only selector below — only an id beats them, and
       without it menus/popovers mounted on <body>, outside the app wrapper,
       keep WhatsApp's green. The rest are the userstyle's, kept as a
       fallback. */
    #whatsapp-web, #whatsapp-web body, #whatsapp-web .app-wrapper-web,
    :root:has(> :not(.dark)), :root:has(> .dark),
    :root .color-refresh, .color-refresh, .dark.color-refresh, .color-refresh.dark,
    .app-wrapper-web.app-wrapper-web, .app-wrapper-web.app-wrapper-web:root,
    .dark .app-wrapper-web.app-wrapper-web, .dark .app-wrapper-web.app-wrapper-web:root {
    ${lines (n: c: "  --WDS-${n}: #{{ ${c}.hex }}; --WDS-${n}-RGB: ${triplet c}; --WDS-${n}-rgb: ${triplet c};\n") wdsSolid}${lines (n: v: let c = builtins.elemAt v 0; in "  --WDS-${n}: rgb({{ ${c}.red }} {{ ${c}.green }} {{ ${c}.blue }} / ${builtins.elemAt v 1}); --WDS-${n}-RGB: ${triplet c}; --WDS-${n}-rgb: ${triplet c};\n") wdsFaded}${lines (n: c: "  --${n}: #{{ ${c}.hex }}; --${n}-rgb: ${triplet c};\n") plainSolid}  --background-default: var(--WDS-surface-default);
      --search-container-background: var(--WDS-surface-default);
    }

    /* The loading splash, before the app's own variables exist. */
    [style^="--splashscreen-startup-background"] {
    ${lines (n: c: "  --${n}: #{{ ${c}.hex }} !important; --${n}-rgb: ${triplet c} !important;\n") splash}}

    [data-icon="wa-wordmark-refreshed"] path { fill: currentcolor; }
    input[type="time"]::-webkit-datetime-edit-hour-field:focus,
    input[type="time"]::-webkit-datetime-edit-minute-field:focus,
    input[type="date"]::-webkit-datetime-edit-year-field:focus,
    input[type="date"]::-webkit-datetime-edit-month-field:focus,
    input[type="date"]::-webkit-datetime-edit-day-field:focus {
      background-color: #{{ primary.hex }};
      color: #{{ onPrimary.hex }};
    }
  '';

  # ZapZap's own window (menu bar, dialogs, settings) doesn't follow the Qt
  # theme caelestia sets: it hardcodes a light and a dark palette in its
  # ThemeManager (WhatsApp green highlights included) and applies them with
  # setPalette + its own stylesheet. So zapzapCaelestia below patches in a
  # few lines that overlay those dictionaries with this rendered JSON (same
  # keys as ZapZap's) when it exists, falling back to stock otherwise.
  zapzapPaletteTemplate = builtins.toJSON (lib.mapAttrs (_: c: "#{{ ${c}.hex }}") {
    window = "surfaceContainer";
    text = "onSurface";
    base = "surfaceContainerHigh";
    alternate_base = "surfaceContainerHighest";
    button = "surfaceContainer";
    button_text = "onSurface";
    highlight = "primary";
    highlighted_text = "onPrimary";
    mid = "outlineVariant";
    placeholder_text = "onSurfaceVariant";
    bright_text = "error";
    accent = "primary";
    accent_text = "onPrimary";
    accent_hover = "primaryFixed";
    accent_border = "primaryFixedDim";
    success = "success";
    success_text = "onSuccess";
    success_hover = "success";
    success_border = "success";
    activity = "tertiary";
    danger = "error";
    danger_text = "onError";
    danger_hover = "error";
    danger_border = "errorContainer";
  });
  zapzapCaelestia = pkgs.zapzap.overridePythonAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      cat >> zapzap/core/theme/theme_manager.py <<'EOF'


      # Added by ~/nixos/home.nix: palette from the current caelestia scheme.
      def _caelestia_palette():
          import json, os
          state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
          try:
              with open(os.path.join(state, "caelestia", "theme", "zapzap-qt.json")) as f:
                  colours = json.load(f)
          except (OSError, ValueError):
              return
          ThemeManager._DARK_PALETTE_COLORS = {**ThemeManager._DARK_PALETTE_COLORS, **colours}
          ThemeManager._LIGHT_PALETTE_COLORS = {**ThemeManager._LIGHT_PALETTE_COLORS, **colours}


      _caelestia_palette()
      EOF
    '';
  });
in
{
  imports = [
    inputs.caelestia-shell.homeManagerModules.default
    inputs.zen-browser.homeModules.beta
    inputs.helium-browser.homeModules.default
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
  # silently breaks without this file existing.
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
    name = cursorTheme;
    size = cursorSize;
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
  # windows do for me. Vesktop rewrites this file on every close, re-
  # setting maximized:true if that's how it was left, so a one-time fix
  # wouldn't stick — this idempotently flips just that one field back on
  # every activation instead, leaving the rest of the file untouched.
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
  # My actual desktop shell (bar, launcher, lock screen, wallpaper picker,
  # notifications...) plus the CLI that drives its dynamic theming.
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

    # The "Keep awake" toggle (utilities panel) is meant to stop the shell's
    # own idle timeouts (lock at 3min, dpms off at 5min, ...) from firing.
    # Upstream does that indirectly: services/IdleInhibitor.qml puts a
    # Wayland idle inhibitor on a 0x0 PanelWindow, and the IdleMonitors are
    # supposed to respect it. But a 0x0 window never gets a buffer, so its
    # layer surface is never mapped, and Hyprland only honours inhibitors on
    # mapped surfaces (see recheckIdleInhibitorStatus() in Hyprland's
    # src/managers/input/IdleInhibitor.cpp). The toggle flips, but nothing is
    # inhibited — it only *seemed* to work sometimes because
    # general.idle.inhibitWhenAudio pauses the timeouts while media plays.
    # This makes IdleMonitors check the toggle directly instead, so it no
    # longer depends on how Hyprland treats the invisible window. Qualified
    # import because that file also imports Quickshell.Wayland, which has its
    # own (non-singleton) IdleInhibitor type with the same name.
    package = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace modules/IdleMonitors.qml \
          --replace-fail 'import qs.services' 'import qs.services
        import qs.services as Services' \
          --replace-fail 'readonly property bool enabled: {' 'readonly property bool enabled: {
                if (Services.IdleInhibitor.enabled)
                    return false;'
      '';
    });

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
        # Its Chromium theming writes a BrowserThemeColor policy into /etc
        # with `sudo -n tee`, only knows chromium/brave/chrome by name — and a
        # policy theme would also block the generated Chrome theme Helium
        # uses instead (see the Helium section below).
        enableChromium = false;
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
        # block caelestia's own scheme-set command. The `rm` drops Helium's
        # compiled theme so its next start rebuilds it from the freshly
        # rendered one (see clearHeliumThemeCache below).
        # vscodeThemeSync keeps VSCodium's theme file current (see the let block).
        postHook = "$HOME/.local/bin/caelestia-spotify-resync.sh & rm -f '${heliumThemeDir}/Cached Theme.pak'; ${vscodeThemeSync} &";
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

    profiles.default = {
      id = 0;
      name = "Default Profile";
      path = zenProfilePath;
      # storeId deliberately left unset: the profiles.ini Zen generated
      # itself (the one this replaces) had no StoreID line either, so this
      # reproduces it exactly rather than opting the profile into Firefox's
      # newer profile-groups handling.

      # The dots' zen/userChrome.css. Purely cosmetic — its colour-mapping
      # section is commented out upstream; colours come from CaelestiaZen
      # instead. What's left: URL bar text centered when unfocused, a pop-in
      # animation for the floating URL bar, rounded search-engine buttons,
      # unloaded tabs dimmed to grayscale, and a small press animation on
      # buttons/tabs. readFile rather than a "${dots}/..." path string: a
      # plain string here is taken as the CSS itself.
      userChrome = builtins.readFile "${dots}/zen/userChrome.css";

      # Sine: the userChrome-JS mod loader CaelestiaZen runs under. The flake
      # handles it declaratively — copies Sine's bootloader into the Zen
      # package and links its (pinned) engine into the profile's chrome/JS.
      sine.enable = true;

      settings = {
        # Firefox-family browsers ignore userChrome.css without this (the
        # dots' own firefox/user.js sets the same pref for the same reason).
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        # Sine updates itself by default: it downloads an updater binary from
        # GitHub, runs it, and overwrites chrome/JS — files that are
        # Nix-managed here, pinned by the zen-browser flake input. Off, so
        # Sine only ever changes through `nix flake update`. The second pref
        # does the same for mods (CaelestiaZen is also marked no-updates in
        # registerCaelestiaZen below).
        "sine.engine.auto-update" = false;
        "sine.auto-updates" = false;

        # Where the CLI renders the template below. Has to be set explicitly:
        # the mod only honours this pref once it has a user value (which Sine
        # only writes when the mod's settings page is first opened), and
        # otherwise falls back to a path hardcoded to its author's home
        # (/home/dim/...) — so out of the box it silently never finds the
        # file.
        "caelestia.zen-sync.chrome-path" = "${config.xdg.stateHome}/caelestia/theme/zen-browser.css";

        # Theme only the browser UI, same scope as caelestia's own Firefox
        # integration. The mod's default also tints every website via Zen
        # Boosts, which changes how every site looks.
        "caelestia.zen-sync.boost-enabled" = false;
      };
    };
  };

  # The CaelestiaZen mod files, straight from the pinned source. Only this
  # one subdirectory is linked, not sine-mods/ itself: Sine writes its own
  # mods.json/chrome.css/content.css in there at runtime, so that directory
  # has to stay writable.
  xdg.configFile."zen/${zenProfilePath}/chrome/sine-mods/caelestia-zen".source = caelestiaZen;

  # The caelestia CLI renders every file in ~/.config/caelestia/templates
  # into ~/.local/state/caelestia/theme on each scheme change ({{ surface.hex }}
  # style placeholders) — that rendered copy is what the mod watches.
  xdg.configFile."caelestia/templates/zen-browser.css".source = "${caelestiaZen}/templates/zen-browser.css";

  # Sine only loads mods listed in sine-mods/mods.json, which it also edits
  # itself at runtime (enable toggles, its own metadata), so it can't be a
  # read-only Nix symlink. This merges CaelestiaZen's entry into whatever's
  # already there on every activation. origin = "store" is what lets Sine run
  # the mod's script at all: it only runs JS from store-installed mods unless
  # the global sine.allow-unsafe-js pref is on, and flipping that would allow
  # JS from *any* mod, not just this one.
  home.activation.registerCaelestiaZen = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mods="${zenProfileDir}/chrome/sine-mods/mods.json"
    $DRY_RUN_CMD mkdir -p "$(dirname "$mods")"
    [ -s "$mods" ] || $DRY_RUN_CMD cp --no-preserve=mode ${pkgs.writeText "sine-mods-empty.json" "{}"} "$mods"
    $DRY_RUN_CMD ${pkgs.jq}/bin/jq --slurpfile mod "${caelestiaZen}/theme.json" \
      '.["caelestia-zen"] = ((.["caelestia-zen"] // {}) + $mod[0] + { enabled: true, origin: "store", "no-updates": true })' \
      "$mods" > "$mods.tmp" \
      && $DRY_RUN_CMD mv "$mods.tmp" "$mods"
  '';

  # --- Helium browser ---
  # Themed with a Chrome theme generated from the scheme (heliumThemeTemplate
  # up top), loaded unpacked on every start. I first used caelestia's own
  # approach, Chromium's BrowserThemeColor policy, but Chrome turns that
  # into an auto-generated theme and clamps its lightness: tested, even the
  # scheme's darkest surface as the seed only got the frame down to about
  # rgb(81,42,42), far lighter than caelestia's near-black. A theme sets the
  # exact colours instead. Trade-offs: Chrome only reads it at startup, so a
  # scheme change shows up the next time Helium starts, not live; and
  # themes have no accent slot, so focus rings/buttons keep Chrome's blue.
  programs.helium = {
    enable = true;
    flags = [ "--load-extension=${heliumThemeDir}" ];
  };

  # The CLI renders the manifest into ~/.local/state/caelestia/theme with the
  # other templates; Chrome needs it named manifest.json inside a directory
  # of its own, and writes its compiled copy ("Cached Theme.pak") next to it
  # — so that directory is a real one, with only the manifest linked in.
  xdg.configFile."caelestia/templates/helium-theme.json".text = heliumThemeTemplate;
  xdg.stateFile."caelestia/helium-theme/manifest.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/caelestia/theme/helium-theme.json";

  # Chrome only rebuilds that compiled copy when it sees a new theme
  # version, and the version (see heliumThemeTemplate) is derived from a few
  # colours, so a scheme differing only elsewhere could keep the stale one.
  # Dropping it after every render makes the next start always rebuild from
  # the current manifest — here for activation, and in the CLI's postHook
  # for scheme changes.
  home.activation.clearHeliumThemeCache = lib.hm.dag.entryAfter [ "renderCaelestiaTemplates" ] ''
    $DRY_RUN_CMD rm -f "${heliumThemeDir}/Cached Theme.pak"
  '';

  # --- ZapZap (WhatsApp) theme ---
  # ZapZap injects every .css file in its global customizations folder into
  # WhatsApp Web when the page loads — its own "Customizations" feature, the
  # same one its settings UI manages. So the scheme reaches it as one more
  # caelestia template (zapzapTemplate up top) linked into that folder.
  # Like Helium it's read at load time, not live: a scheme change shows up
  # the next time ZapZap starts (or on a page reload, Ctrl+R). Its own Qt
  # window (menu bar, dialogs) gets the scheme separately, through
  # zapzap-qt.json and the zapzapCaelestia patch in the let block.
  xdg.configFile."caelestia/templates/zapzap.css".text = zapzapTemplate;
  xdg.configFile."caelestia/templates/zapzap-qt.json".text = zapzapPaletteTemplate;
  xdg.dataFile."ZapZap/customizations/global/css/caelestia.css".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/caelestia/theme/zapzap.css";

  # Global CSS is off until switched on (ZapZap's custom/global/css/enabled
  # setting, false by default). ZapZap owns ZapZap.conf — it rewrites window
  # geometry and every settings change there — so this only sets that one
  # key, in QSettings' INI layout ([custom] section, backslash-separated
  # subkeys), and leaves the rest of the file alone.
  home.activation.enableZapzapCss = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    conf="${config.xdg.configHome}/ZapZap/ZapZap.conf"
    $DRY_RUN_CMD mkdir -p "$(dirname "$conf")"
    [ -e "$conf" ] || $DRY_RUN_CMD touch "$conf"
    $DRY_RUN_CMD ${pkgs.gawk}/bin/awk '
      /^\[custom\]$/ { print; print "global\\css\\enabled=true"; found = 1; section = 1; next }
      /^\[/ { section = 0 }
      section && /^global\\css\\enabled=/ { next }
      { print }
      END { if (!found) { print ""; print "[custom]"; print "global\\css\\enabled=true" } }
    ' "$conf" > "$conf.tmp" \
      && $DRY_RUN_CMD mv "$conf.tmp" "$conf"
  '';

  # --- Steam (Millennium) theme ---
  # The Material theme (steamMaterialTheme up top), where Millennium looks
  # for themes, and the template its Matugen option ends up reading.
  xdg.dataFile."Steam/millennium/themes/Material-Theme".source = steamMaterialTheme;
  xdg.configFile."caelestia/templates/steam-material.css".text = steamMaterialTemplate;

  # Millennium owns its config.json (settings changed in its UI land there),
  # so like mods.json for Zen this merges in only what the integration needs
  # on every activation: Material as the active theme, its colour option set
  # to Matugen, and update checks off — Millennium and the theme are pinned
  # here and move with this repo, so their in-app update prompts would only
  # point at versions Nix won't install. Everything else is left to
  # Millennium, which fills its own defaults in around these keys.
  home.activation.configureMillennium = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg="${config.xdg.configHome}/millennium/config.json"
    $DRY_RUN_CMD mkdir -p "$(dirname "$cfg")"
    [ -s "$cfg" ] || $DRY_RUN_CMD cp --no-preserve=mode ${pkgs.writeText "millennium-empty.json" "{}"} "$cfg"
    $DRY_RUN_CMD ${pkgs.jq}/bin/jq '
      .themes.activeTheme = "Material-Theme"
      | .themes.conditions["Material-Theme"].Color = "Matugen"
      | .general.checkForMillenniumUpdates = false
      | .general.checkForPluginAndThemeUpdates = false
    ' "$cfg" > "$cfg.tmp" \
      && $DRY_RUN_CMD mv "$cfg.tmp" "$cfg"
  '';

  # --- caelestia user templates ---
  # The CLI only renders ~/.config/caelestia/templates on a scheme change,
  # so a template added or changed here would do nothing until the next
  # wallpaper/scheme switch — which is exactly why Zen showed no colours
  # after the first deploy. This renders them once per activation with the
  # CLI's own apply_user_templates() and the current scheme, i.e. the same
  # output a scheme change would produce, without re-applying everything
  # else a real one does. Runs after linkGeneration so the template
  # symlinks are already in place. Non-fatal: if a CLI update ever moves
  # these functions, the next real scheme change still renders everything.
  home.activation.renderCaelestiaTemplates = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -f "${config.xdg.stateHome}/caelestia/scheme.json" ]; then
      $DRY_RUN_CMD ${caelestiaCliPython} -c 'from caelestia.utils.scheme import get_scheme; from caelestia.utils.theme import apply_user_templates; s = get_scheme(); apply_user_templates(s.colours, s.mode)' \
        || echo "renderCaelestiaTemplates: rendering failed; templates render on the next scheme change instead" >&2
    fi
  '';

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

    bibata-cursors  # cursor theme binary, wired up via home.pointerCursor above

    vscodiumCaelestia  # code editor (VSCodium, with the caelestia theme synced before launch — see the let block)

    bitwarden-desktop  # password manager desktop app

    # Discord client. Vencord's built in, so theming/plugins work without
    # extra setup beyond enabling the theme once in its own settings.
    vesktop  # Discord client

    spicetify-cli  # patches Spotify with the caelestia theme (Spotify itself comes from Flatpak, below, so this has something writable to patch)

    # adw-gtk3 is the Adwaita-based GTK3 theme whose symbolic colours
    # (accent_color, window_bg_color, ...) caelestia's gtk.css template
    # overrides on every switch — without it there's nothing for that CSS
    # to actually restyle. papirus-folders is the tool that recolors the
    # Papirus folder icons (see seedPapirusIcons above for the setup that
    # makes it able to run at all).
    adw-gtk3         # Adwaita-based GTK3 theme, restyled by caelestia's gtk.css
    papirus-folders  # recolors Papirus folder icons on every theme switch

    # Archive support. thunar-archive-plugin itself is NOT listed here — it
    # has to be built into Thunar via programs.thunar.plugins
    # (configuration.nix) to actually be picked up, so Thunar itself also
    # lives there now, not as a plain package in this profile.
    #
    # engrampa, not xarchiver: thunar-archive-plugin doesn't just shell out
    # to whatever's set as my default archive app — it only ships wrapper
    # scripts (libexec/thunar-archive-plugin/*.tap) for a fixed short list
    # of managers: ark, engrampa, file-roller. I had xarchiver here first
    # since it's the lighter GTK option, but it's not on that list, so the
    # plugin filtered it straight back out and every Compress/Extract just
    # failed with "No suitable archive manager found" even though xarchiver
    # itself worked fine standalone. engrampa is the lightest of the three
    # the plugin actually supports, and it drives the same zip/unzip/p7zip
    # below as its backend, so nothing else here needed to change.
    unzip          # extracts .zip
    zip            # creates .zip
    p7zip          # .7z and a bunch of other formats via 7z
    engrampa       # archive-manager backend the Thunar plugin calls out to

    zapzapCaelestia  # WhatsApp desktop client, patched to take its palette from caelestia (see the let block)

    # Wine prefix manager, for Windows apps I don't have a native Linux
    # build for (Rave, so far). Each app gets its own isolated
    # prefix/runner, so they can't collide with each other's dependencies.
    # I already have 32-bit graphics (hardware.graphics.enable32Bit) and
    # audio (pipewire alsa.support32Bit) enabled in configuration.nix for
    # Steam/Proton, which covers what Wine needs too.
    bottles

    # Misc utilities the shell/CLI lean on directly
    playerctl       # media player control (play/pause/next), used by bar/OSD widgets
    brightnessctl   # backlight control, used by the brightness OSD
    grim            # takes the actual screenshot (screencopy)
    slurp           # interactive region selector, used by grim/grimblast for area captures
    grimblast       # freeze-then-select screenshots (hyprpicker under the hood)
    cliphist        # clipboard history, backing the clipboard-history picker
    wl-clipboard    # wl-copy/wl-paste, used to copy screenshots to the clipboard
    libnotify       # notify-send, used for screenshot/save notifications

    dart-sass            # compiles the live Discord theme CSS
    app2unit             # used by the CLI to launch toggled apps
    gpu-screen-recorder  # backs `caelestia record`
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
        kb_layout = "${keyboardLayout}",
        kb_variant = "${keyboardVariant}",
      },
    })

    -- Cursor theme again, natively for Wayland/hyprcursor clients this time
    -- (home.pointerCursor above covers GTK/X11). Set explicitly because
    -- greetd execs Hyprland directly rather than through a login shell, so
    -- home-manager's session-vars script may not have run by the time this
    -- matters.
    hl.env("XCURSOR_THEME", "${cursorTheme}")
    hl.env("XCURSOR_SIZE", "${toString cursorSize}")

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

    -- Monitor layout, from variables.nix — primaryMonitor on the left at
    -- its native refresh rate, secondaryMonitor to its right. Without this
    -- Hyprland re-picks its own defaults on every output re-enumeration
    -- (e.g. after lock/DPMS), which is why it kept reverting to a lower
    -- refresh rate / swapping sides on me.
    hl.monitor({
      output = "${primaryMonitor.output}",
      mode = "${primaryMonitor.mode}",
      position = "${primaryMonitor.position}",
      scale = 1,
    })
    hl.monitor({
      output = "${secondaryMonitor.output}",
      mode = "${secondaryMonitor.mode}",
      position = "${secondaryMonitor.position}",
      scale = 1,
      transform = ${toString secondaryMonitor.transform},
    })

    -- No locking on session start here — greetd (configuration.nix)
    -- autologs into Hyprland straight away, with LUKS (disko.nix) already
    -- gating access at boot, so a lock screen immediately after would just
    -- be redundant.
    hl.on("hyprland.start", function()
      -- The dots' own execs.lua unconditionally runs
      -- `hyprctl setcursor sweet-cursors 24` in its own "hyprland.start"
      -- handler, which loads before this file — sweet-cursors isn't even
      -- installed, and no env var overrides a hardcoded call like that.
      -- Re-issuing it here (this file loads last) wins, since whichever
      -- `hyprctl setcursor` call runs last is what sticks. The sleep is
      -- slack against exec_cmd not being blocking.
      hl.exec_cmd("sleep 1 && hyprctl setcursor ${cursorTheme} ${toString cursorSize} "
        .. "&& gsettings set org.gnome.desktop.interface cursor-theme ${cursorTheme} "
        .. "&& gsettings set org.gnome.desktop.interface cursor-size ${toString cursorSize}")
    end)

    -- The dots' own keybinds.lua binds Print (and Super+Shift+S /
    -- Super+Shift+Alt+S) to `caelestia screenshot`, which always stages a
    -- copy in ~/.cache/caelestia/screenshots first and only moves it to
    -- ~/Pictures/Screenshots if you click "Save" on the popup notification
    -- — otherwise it just sits in cache forever. My own scripts below
    -- replace that entirely (freeze + region/full capture, straight to
    -- Pictures/Screenshots every time), so I unbind the dots' defaults
    -- first. Must run before my own hl.bind("Print", ...) below: hl.unbind
    -- matches by key combo alone, with no notion of which bind owns it, so
    -- calling it after my own bind exists would remove mine too. This
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
