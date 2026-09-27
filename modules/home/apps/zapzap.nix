{ config, pkgs, lib, ... }:

# ZapZap (WhatsApp desktop client), themed from the caelestia scheme in two
# parts: WhatsApp Web itself (CSS) and ZapZap's own Qt window (a patch).
# Neither is live: both are read when ZapZap starts (the CSS also on a page
# reload, Ctrl+R).
let
  # WhatsApp Web's CSS, as a caelestia template. WhatsApp colours its UI
  # through its design system's --WDS-* custom properties (each with
  # -RGB/-rgb "r, g, b" twins for rgba() use) plus a few older
  # --name/--name-rgb pairs; the variable list and selectors follow
  # Catppuccin's WhatsApp Web userstyle (catppuccin/userstyles,
  # styles/whatsapp-web). Mapped onto caelestia's Material roles rather than
  # the scheme's Catppuccin-named keys: in dark dynamic schemes those
  # collapse (base/mantle/crust are all near-black, and so is overlay2,
  # Catppuccin's secondary-text colour), so secondary text would vanish.
  # Translucent ones use rgb(... / alpha) with the base colour's triplet,
  # like the userstyle's fade().
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
       modules/home/apps/zapzap.nix in ~/nixos. The #whatsapp-web ones (the id on
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

  # ZapZap's own window (menu bar, dialogs, settings) ignores the Qt theme:
  # its ThemeManager hardcodes a light and a dark palette (WhatsApp green
  # highlights included) and applies them itself. The patch below overlays
  # both with this rendered JSON (same keys as ZapZap's) when it exists, and
  # falls back to stock otherwise. The patch means ZapZap is built locally
  # instead of coming from the binary cache.
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


      # Added by ~/nixos/modules/home/apps/zapzap.nix: palette from the current caelestia scheme.
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
  home.packages = [ zapzapCaelestia ];

  # ZapZap injects every .css file in its global customizations folder into
  # WhatsApp Web on page load — its own "Customizations" feature. The
  # rendered template is linked in there.
  xdg.configFile."caelestia/templates/zapzap.css".text = zapzapTemplate;
  xdg.configFile."caelestia/templates/zapzap-qt.json".text = zapzapPaletteTemplate;
  xdg.dataFile."ZapZap/customizations/global/css/caelestia.css".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/caelestia/theme/zapzap.css";

  # Global CSS stays off until ZapZap's custom/global/css/enabled setting is
  # on. ZapZap owns ZapZap.conf (it rewrites window geometry and every
  # setting there), so this sets only that one key, in QSettings' INI layout
  # ([custom] section, backslash-separated subkeys), on every activation.
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
}
