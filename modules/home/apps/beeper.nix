{ config, pkgs, lib, ... }:

# Beeper (one inbox for WhatsApp, Telegram, Signal, Instagram, ...), themed
# from the caelestia scheme through Beeper's own custom CSS feature: it
# injects ~/.config/BeeperTexts/custom.css into its windows as a <style>
# tag. Not live: Beeper reads that file at startup and on "Reload custom
# CSS" in its command bar, not when it changes.
let
  # Beeper's stylesheet colours everything through custom properties, in
  # three layers that all end up in use: Material-named legacy ones
  # (--color-primary, --color-on-surface, --color-secondary-container, ...),
  # the newer --appearance-color-* (which --semantic-colors-*, the chat
  # bubbles and the buttons resolve to), and the --theme-* ramps those are
  # built from. Each is mapped onto caelestia's Material roles here, by
  # meaning rather than name: Beeper's "secondary container", say, is a
  # neutral fill, so it gets a surface container, not the scheme's tinted
  # secondaryContainer.
  #
  # Everything is set on both :root and body, as !important: Beeper's dark
  # values come from :root[data-theme=dark] (more specific than :root), and
  # its optional in-app themes (Settings > Appearance) redefine some on
  # body. Light/dark doesn't need handling here: the scheme's colours are
  # written whatever Beeper's mode is, and Beeper's mode follows the desktop
  # (its theme setting defaults to System), like caelestia's own.
  rgb = c: "{{ ${c}.red }} {{ ${c}.green }} {{ ${c}.blue }}";
  solid = c: "#{{ ${c}.hex }}";
  faded = c: alpha: "rgb(${rgb c} / ${alpha})";

  # Beeper's accent/danger/warning ramps step from 25 to 1000; these are the
  # opacities its stock palette uses at each step (blueribbon, red, orange).
  rampAlphas = {
    "25" = "0.14"; "50" = "0.26"; "100" = "0.36"; "200" = "0.44";
    "300" = "0.53"; "400" = "0.6"; "500" = "0.66"; "600" = "0.72";
    "700" = "0.77"; "800" = "0.83"; "900" = "0.87"; "950" = "0.91";
    "975" = "0.95"; "1000" = "1";
  };
  ramp = prefix: c: lib.mapAttrs' (step: alpha: lib.nameValuePair "${prefix}-${step}" (faded c alpha)) rampAlphas;

  # --appearance-alpha-N is white at N% in dark mode and black in light mode,
  # i.e. the foreground colour; the -inverse ones are the background colour.
  alphaRamp = prefix: c: lib.listToAttrs (map (n:
    lib.nameValuePair "${prefix}-${toString n}" (faded c (if n < 10 then "0.0${toString n}" else "0.${toString n}"))
  ) [ 0 1 2 3 5 6 8 10 15 20 30 40 50 60 70 80 90 95 ]);

  tokens =
    # Accent: Beeper's light ramp fills (buttons, outgoing bubbles), its dark
    # ramp is text and borders on dark backgrounds; Material's primary
    # already works as both. Warning has no Material role; tertiary is the
    # usual stand-in, and comes with an on-colour.
    ramp "theme-main-alpha-light" "primary"
    // ramp "theme-main-alpha-dark" "primary"
    // ramp "theme-danger-alpha" "error"
    // ramp "theme-warning-alpha" "tertiary"
    // alphaRamp "appearance-alpha" "onSurface"
    // alphaRamp "appearance-alpha-inverse" "surface"
    // lib.mapAttrs (_: solid) {
      # --- the --appearance-color-* layer ---
      appearance-color-bg-primary = "surface";
      appearance-color-bg-primary-elevated = "surfaceContainer";
      appearance-color-bg-secondary = "surfaceContainer";
      appearance-color-bg-secondary-elevated = "surfaceContainerHigh";
      appearance-color-bg-dark = "surfaceContainerLowest";
      appearance-color-bg-inverse = "inverseSurface";
      appearance-color-bubble-in-bg = "surfaceContainerHigh";
      appearance-color-border-emphasis = "outline";
      appearance-color-text-primary = "onSurface";
      appearance-color-text-secondary = "onSurfaceVariant";
      appearance-color-text-tertiary = "outline";
      appearance-color-text-quaternary = "outlineVariant";
      appearance-color-text-inverse = "inverseOnSurface";
      appearance-color-text-on-main = "onPrimary";
      appearance-color-text-on-danger = "onError";
      appearance-color-text-on-warning = "onTertiary";
      main-dark-text-on-main = "onPrimary";
      main-light-text-on-main = "onPrimary";

      # --- the legacy --color-* layer ---
      color-primary = "primary";
      color-brand = "primary";
      color-base-system-blue-80 = "primary";
      color-base-system-blue-90 = "primary";
      color-base-system-blue-100 = "primary";
      color-base-system-blue-110 = "primary";
      color-bg = "surface";
      color-fg = "onSurface";
      color-surface = "surface";
      color-surface-dim = "surfaceDim";
      color-surface-dark = "onSurface";  # Beeper's "the other end": black in light mode, white in dark
      color-on-surface = "onSurface";
      color-on-surface-variant = "onSurfaceVariant";
      color-primary-container = "surfaceContainer";
      color-secondary-container = "surfaceContainerHigh";
      color-container-inside-secondary-container = "surfaceContainerHighest";
      color-tertiary-container = "surfaceContainerLow";
      color-container-content-base-1 = "onSurfaceVariant";
      color-on-secondary-container = "onSurfaceVariant";
      color-on-tertiary-container = "onSurfaceVariant";
      color-on-error-container = "error";
      color-outline = "outlineVariant";
      color-outline-variant = "primaryContainer";  # an accent-tinted outline in Beeper
      color-highlight-reaction = "primaryContainer";
      color-delete = "error";
      color-background-app-weak = "surfaceContainerLow";
      color-background-button-primary = "primary";
      color-background-button-secondary = "surfaceContainerHighest";
      color-background-button-secondary-active = "surfaceContainerHigh";
      color-background-button-secondary-disabled = "surfaceContainerHigh";
      color-background-button-danger = "error";
      color-background-elevated = "surfaceContainer";
      color-background-elevated-hover = "surfaceContainerHigh";
      color-background-emoji-mart = "surfaceContainer";
      color-background-grouped = "surfaceContainerLow";
      color-background-grouped-weak = "surface";
      color-background-input = "surfaceContainerHighest";
      color-background-menu-opaque = "surfaceContainer";
      color-background-menu-option-hover = "primary";
      color-background-message-bubble-received = "surfaceContainerHigh";
      color-background-object = "surfaceContainer";
      color-background-segmentedcontrol = "surfaceContainerHigh";
      color-background-select = "surfaceContainerHighest";
      color-background-select-disabled = "surfaceContainerHigh";
      color-background-selected-primary = "primary";
      color-border-button-secondary = "outlineVariant";
      color-border-button-secondary-active = "outline";
      color-border-input = "outlineVariant";
      color-border-input-active = "outline";
      color-border-message-bubble-suggested = "primary";
      color-border-neutrals = "outlineVariant";
      color-icon-neutrals = "onSurfaceVariant";
      color-icon-neutrals-strong = "onSurface";
      color-icon-neutrals-weak = "outline";
      color-text-button-secondary = "onSurface";
      color-text-button-secondary-disabled = "onSurfaceVariant";
      color-text-danger = "error";
      color-text-info = "primary";
      color-text-success = "success";
      color-text-neutrals = "onSurface";
      color-text-neutrals-subtle = "outline";
      color-text-neutrals-weak = "onSurfaceVariant";
      color-text-primary = "onSurface";
      color-text-secondary = "onSurfaceVariant";
      color-text-tertiary = "outline";
    }
    // lib.mapAttrs (_: v: faded (builtins.elemAt v 0) (builtins.elemAt v 1)) {
      appearance-color-text-inverse-secondary = [ "inverseOnSurface" "0.6" ];
      appearance-color-text-inverse-tertiary = [ "inverseOnSurface" "0.27" ];
      appearance-color-border-secondary = [ "onSurface" "0.1" ];
      appearance-color-border-tertiary = [ "onSurface" "0.14" ];
      appearance-glass-neutral-fill = [ "outlineVariant" "0.46" ];
      appearance-translucent-neutral-fill-prominent = [ "outlineVariant" "0.36" ];

      # Not primaryDim/errorDim: most of caelestia's preset schemes lack them.
      color-background-button-primary-active = [ "primary" "0.85" ];
      color-background-button-primary-disabled = [ "primary" "0.5" ];
      color-background-button-danger-active = [ "error" "0.85" ];
      color-background-button-danger-disabled = [ "error" "0.5" ];
      color-background-button-translucent = [ "onSurface" "0.1" ];
      color-background-button-translucent-active = [ "onSurface" "0.15" ];
      color-background-commandbar = [ "surfaceContainer" "0.85" ];
      color-background-header-right = [ "surfaceContainer" "0.9" ];
      color-background-kbd = [ "onSurface" "0.15" ];
      color-background-menu = [ "surfaceContainer" "0.9" ];
      color-background-menu-badge = [ "onSurface" "0.1" ];
      color-background-scrollbar = [ "onSurface" "0.3" ];
      color-background-scrollbar-hover = [ "onSurface" "0.5" ];
      color-background-tag = [ "onSurface" "0.1" ];
      color-border-neutrals-weak = [ "onSurface" "0.08" ];
      color-border-translucent = [ "onSurface" "0.1" ];
      color-border-translucent-strong = [ "onSurface" "0.15" ];
      color-border-translucent-weak = [ "onSurface" "0.05" ];
      color-icon-translucent = [ "onSurface" "0.6" ];
      color-icon-translucent-strong = [ "onSurface" "0.9" ];
      color-icon-translucent-weak = [ "onSurface" "0.4" ];
      color-text-translucent = [ "onSurface" "0.9" ];
      color-text-translucent-subtle = [ "onSurface" "0.5" ];
      color-text-translucent-weak = [ "onSurface" "0.7" ];
      color-text-danger-active = [ "error" "0.8" ];
      color-text-danger-disabled = [ "error" "0.6" ];
      color-text-info-active = [ "primary" "0.8" ];
      color-text-info-disabled = [ "primary" "0.6" ];
      color-text-on-accent-weak = [ "onPrimary" "0.7" ];
      color-bg-fill-primary = [ "onSurface" "0.08" ];
      color-bg-fill-secondary = [ "onSurface" "0.12" ];
      color-scrim = [ "surface" "0.55" ];
      color-glass-surface = [ "surface" "0.38" ];
      color-glass-container = [ "surface" "0.15" ];
      color-delete-background = [ "error" "0.12" ];
    }
    // {
      # Every other --color-*-rgb follows its colour by itself
      # (`from var(--color-x) r g b`); this one is built from white.
      color-on-primary-rgb = "from ${solid "onPrimary"} r g b";
      # Beeper's purple-to-blue brand gradient (onboarding buttons and
      # headings, Plus pills, the login QR code's frame). Flat primary: a
      # second tone would leave onPrimary text unreadable on part of it in
      # light schemes.
      gradient-brand = "linear-gradient(${solid "primary"}, ${solid "primary"})";
    };

  beeperTemplate = ''
    /* Rendered by the caelestia CLI on every scheme change — see
       modules/home/apps/beeper.nix in ~/nixos. Edits here last until the
       next scheme change; change the template there instead. */
    :root, body {
    ${lib.concatStrings (lib.mapAttrsToList (n: v: "  --${n}: ${v} !important;\n") tokens)}}

    :root { color-scheme: {{ mode }}; }

    /* Text Beeper hardcodes as white on top of the accent (unread counts on
       account icons, the selected @mention suggestion, dialog and form
       buttons, "read more" in your own bubbles, the onboarding's main
       button): unreadable on a light primary. */
    .AccountBadge-module__dot.AccountBadge-module__unreadWithNumber,
    .TextAreaAutocomplete-module__selected,
    .styled-inputs button.primary,
    .dialog-container button.confirm,
    .feedback-button button,
    .bridge-name .bridge-type,
    .bubble-mode .is-sender .read-more-button:not(.error) { color: ${solid "onPrimary"}; }
    .BrandButton-module__button.BrandButton-module__primary { --brand-button-foreground: ${solid "onPrimary"}; }
  '';
in
{
  home.packages = [ pkgs.beeper ];

  # The rendered template is linked in as Beeper's custom CSS file.
  xdg.configFile."caelestia/templates/beeper.css".text = beeperTemplate;
  xdg.configFile."BeeperTexts/custom.css".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/caelestia/theme/beeper.css";
}
