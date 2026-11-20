{ pkgs, inputs, username, ... }:

# Steam (with the Millennium client-modding framework and a caelestia-themed
# skin), gamescope and GameMode.
let
  # Millennium (flake input, see flake.nix), straight from its `packages`
  # output: built against this system's nixpkgs (the input's nixpkgs
  # follows ours), with Bun from its own pinned nixpkgs-bun.
  millennium = inputs.millennium.packages.${pkgs.stdenv.hostPlatform.system}.millennium;
in
{
  programs.steam = {
    enable = true;
    # Steam with Millennium injected, through Millennium's own wrapper
    # (steam.nix in the input) applied to this system's Steam rather than
    # the one in Millennium's pinned nixpkgs. It adds Millennium's libraries
    # to Steam's FHS env and, on every launch, symlinks
    # ~/.local/share/Steam/ubuntu12_{32,64}/libXtst.so.6 to Millennium's
    # bootstrap library — that's how Steam loads it. Only the client UI is
    # affected, not games.
    #
    # If Millennium is ever removed, delete those two symlinks by hand, or
    # Steam keeps trying to load a library that no longer exists.
    package = pkgs.callPackage "${inputs.millennium}/steam.nix" { inherit millennium; };
    remotePlay.openFirewall = true;      # Remote Play ports
    dedicatedServer.openFirewall = true; # ports for hosting game servers
    # A "Steam (gamescope)" session where gamescope is the only compositor.
    # -f: games always run fullscreen, since there's no window manager to
    # un-fullscreen into.
    gamescopeSession = {
      enable = true;
      args = [ "-f" "--adaptive-sync" ];
    };
  };

  # capSysNice is off because its setuid wrapper breaks gamescope when
  # launched from a game's Launch Options (`gamescope ... -- %command%`):
  # Steam sets no_new_privs on that process chain, the kernel then refuses
  # the wrapper's file capability, and gamescope exits with "failed to
  # inherit capabilities: Operation not permitted". GameMode (below) already
  # renices games, so per-game gamescope matters more.
  programs.gamescope = {
    enable = true;
    capSysNice = false;
  };

  # GameMode applies performance tweaks (CPU governor, I/O priority,
  # niceness) while a game runs. Steam uses it automatically; anything else
  # needs `gamemoderun %command%` in its launch options.
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        renice = 10; # nice level applied to the game process
      };
    };
  };

  # --- Caelestia theme for the Steam client ---
  # The Material theme for Millennium, with its "Matugen" colour option fed
  # from the current caelestia scheme. That option re-reads its colour file
  # every 1.5s, so Steam follows scheme changes live, without a restart.
  home-manager.users.${username} = { config, lib, pkgs, ... }: let
    # Pinned by rev + hash (not a flake input) because it runs JavaScript
    # inside the Steam client: bumping it should mean reading the new
    # version first. Its colour file css/main/colors/matugen.css is replaced
    # with a symlink to the copy the caelestia CLI renders from the template
    # below.
    steamMaterialTheme = pkgs.runCommand "steam-material-theme-caelestia" { } ''
      cp -r --no-preserve=mode ${pkgs.fetchFromGitHub {
        owner = "kuska1";
        repo = "Material-Theme";
        rev = "114522b6db129a6f87eb4eb89195ef277656ac20";
        hash = "sha256-Ss4D+xIvJUKX62QDqpzww4NCicG3ljwMFa5S97QAL8c=";
      }} $out
      ln -sf ${config.xdg.stateHome}/caelestia/theme/steam-material.css $out/css/main/colors/matugen.css
      cat ${storeHeaderCss} >> $out/css/main/web/store.css
    '';

    # The store's header bar (Browse, Recommendations, ..., search) stayed
    # Steam-blue: the theme only rounds its search form, and its colour
    # rules for the search button are for older class names. These recolour
    # the bar, the shadow strip under it, the search field and the search
    # button with the theme's own variables. Steam's class names are hashes
    # that change when it rebuilds its store (the theme collects several
    # generations of them), so if the bar turns blue again, the names below
    # need refreshing; data-featuretarget="store-menu-v7" is the stable
    # element the header renders into.
    storeHeaderCss = pkgs.writeText "steam-store-header.css" ''

      /* caelestia: store header colours (modules/gaming/steam.nix) */
      body .XLbP8xOkCYw- {
          background: var(--md-sys-color-surface-container);
      }
      body [data-featuretarget="store-menu-v7"] .hjG2apu1gQc- {
          background: unset;
      }
      body form.Tx-rbJxeMFs- {
          background: var(--md-sys-color-surface-container-highest);
      }
      body form.Tx-rbJxeMFs- .A42lZ-U1dhI- {
          border-style: none;
          box-shadow: unset;
          background: unset;
          color: var(--md-sys-color-on-surface-variant);
      }
    '';

    # Every --md-sys-color-* variable the theme reads, in caelestia's
    # camelCase scheme names (the template converts them to kebab-case).
    # The theme's own matugen.css uses rgb(...) values, which is what the
    # CLI's `.rgb` produces.
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
         modules/gaming/steam.nix in ~/nixos. */
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
  in {
    # Where Millennium looks for themes.
    xdg.dataFile."Steam/millennium/themes/Material-Theme".source = steamMaterialTheme;
    # Rendered into ~/.local/state/caelestia/theme on every scheme change
    # (see home/caelestia.nix).
    xdg.configFile."caelestia/templates/steam-material.css".text = steamMaterialTemplate;

    # Millennium owns its config.json (its settings UI writes there), so
    # this only merges in what the theme needs, on every activation:
    # Material as the active theme, its colour option set to Matugen, and
    # update checks off — Millennium and the theme are pinned here, so their
    # in-app update prompts would point at versions Nix won't install.
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
  };
}
