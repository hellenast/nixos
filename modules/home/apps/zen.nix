{ config, pkgs, lib, inputs, ... }:

# Zen browser (the default browser), live-themed from the caelestia scheme
# through CaelestiaZen, a community Sine mod, plus the dots' cosmetic
# userChrome.css.
#
# Why a mod: caelestia's official Firefox route (the CaelestiaFox extension
# and native host in the dots' firefox/ dir) pushes colours through
# Firefox's theme API, which Zen mostly ignores, and upstream marks Zen
# theming won't-fix (caelestia-dots/caelestia#148, #424). CaelestiaZen
# instead reads the CLI's scheme.json (~/.local/state/caelestia) from its
# chrome script and injects the colours into Zen's UI, reloading them
# whenever the file changes. Since 2.0 it also restyles Zen as an M3
# Expressive app and follows caelestia's light/dark mode; both can be
# switched off in the mod's Sine settings.
let
  dots = inputs.caelestia-dots-src;

  # Pinned by rev + hash rather than as a flake input, so `nix flake
  # update` leaves it alone: it runs with full browser privileges, so a bump
  # should mean reading the new theme-sync.uc.js first (docs/deploying.md),
  # then editing rev/hash. This is 2.0.0.
  caelestiaZen = pkgs.fetchFromGitHub {
    owner = "dim-ghub";
    repo = "CaelestiaZen";
    rev = "a46830994eef22c2b6d8cc355baea36c7a400afd";
    hash = "sha256-DHLkITD83thWrQ0VQfd1FJ+DLxi3xO+1h/f95hNTYBU=";
  };

  # The profile directory Zen created on its first launch. Declaring the
  # profile below makes home-manager own ~/.config/zen/profiles.ini, so this
  # must match the existing directory exactly, or Zen opens a new, empty
  # profile (the old one stays on disk, unused). On a fresh install
  # home-manager creates this same name, so it isn't tied to this machine.
  zenProfilePath = "kn7ftk1l.Default Profile";
  zenProfileDir = "${config.xdg.configHome}/zen/${zenProfilePath}";
in
{
  imports = [ inputs.zen-browser.homeModules.beta ];

  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;

    profiles.default = {
      id = 0;
      name = "Default Profile";
      path = zenProfilePath;
      # storeId left unset: the profiles.ini Zen generated itself had no
      # StoreID either, and setting one opts the profile into Firefox's
      # newer profile-groups handling.

      # The dots' zen/userChrome.css. Cosmetic only (its colour section is
      # commented out upstream; colours come from CaelestiaZen): URL bar
      # text centred when unfocused, a pop-in animation for the floating URL
      # bar, rounded search-engine buttons, unloaded tabs in grayscale, a
      # small press animation on buttons/tabs. readFile, because a plain
      # string here is taken as the CSS itself, not a path.
      userChrome = builtins.readFile "${dots}/zen/userChrome.css";

      # Sine: the userChrome-JS mod loader CaelestiaZen runs under. The flake
      # installs its bootloader into the Zen package and links its (pinned)
      # engine into the profile's chrome/JS.
      sine.enable = true;

      settings = {
        # Firefox-based browsers ignore userChrome.css without this.
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        # Sine updates itself by default, downloading and running an updater
        # that overwrites chrome/JS — files that are Nix-managed and pinned
        # by the zen-browser flake input here. Off, for Sine and for mods
        # (CaelestiaZen is also marked no-updates in registerCaelestiaZen).
        "sine.engine.auto-update" = false;
        "sine.auto-updates" = false;

        # Theme only the browser UI, like caelestia's own Firefox
        # integration. The mod's default ("balanced") also tints every
        # website through Zen Boosts. Set here, it wins over the mod's
        # settings page on every start.
        "caelestia.zen.tint" = "off";
      };
    };
  };

  # The mod's files, straight from the pinned source. Only its own
  # subdirectory is linked, not sine-mods/ itself: Sine writes
  # mods.json/chrome.css/content.css there at runtime, so that directory
  # must stay writable.
  xdg.configFile."zen/${zenProfilePath}/chrome/sine-mods/caelestia-zen".source = caelestiaZen;

  # Sine only loads mods listed in sine-mods/mods.json, which it also edits
  # itself (enable toggles, metadata), so it can't be a read-only symlink.
  # This merges CaelestiaZen's entry into it on every activation.
  # origin = "store" is what lets Sine run the mod's script: it only runs JS
  # from store-installed mods, unless the global sine.allow-unsafe-js pref
  # is on — which would allow JS from any mod.
  home.activation.registerCaelestiaZen = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mods="${zenProfileDir}/chrome/sine-mods/mods.json"
    $DRY_RUN_CMD mkdir -p "$(dirname "$mods")"
    [ -s "$mods" ] || $DRY_RUN_CMD cp --no-preserve=mode ${pkgs.writeText "sine-mods-empty.json" "{}"} "$mods"
    $DRY_RUN_CMD ${pkgs.jq}/bin/jq --slurpfile mod "${caelestiaZen}/theme.json" \
      '.["caelestia-zen"] = ((.["caelestia-zen"] // {}) + $mod[0] + { enabled: true, origin: "store", "no-updates": true })' \
      "$mods" > "$mods.tmp" \
      && $DRY_RUN_CMD mv "$mods.tmp" "$mods"
  '';
}
