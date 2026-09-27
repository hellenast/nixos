# Caelestia theming

caelestia-cli re-themes the desktop on every wallpaper/scheme change. Most of that is automatic (GTK/Qt, terminal, Hyprland, btop, fuzzel, Papirus folders). The apps below are integrated by this repo and each has something to know or do once.

How the integrations plug in (`modules/home/caelestia.nix`):
- **User templates** — files in `~/.config/caelestia/templates` with `{{ colour.hex }}`-style placeholders, rendered into `~/.local/state/caelestia/theme/` on every scheme change *and* on every home-manager activation (so a fresh deploy has colours without waiting for a wallpaper change).
- **`caelestia.postHooks`** — commands run in the background after every scheme change.

## Spotify (`home/apps/spotify.nix`)

- Installed as a user-scope Flatpak so spicetify can patch it. Log into Spotify normally on first launch — that also creates `~/.var/app/com.spotify.Client/config/spotify/prefs`, which the next step needs.
- One-time spicetify setup after that first login (spicetify's own state, not something home-manager writes):
  ```
  spicetify config current_theme caelestia color_scheme caelestia prefs_path ~/.var/app/com.spotify.Client/config/spotify/prefs
  spicetify backup apply
  ```
  Skipping this leaves `current_theme`/`color_scheme` blank, and every later `spicetify apply` silently applies no theme at all.
- No live sync: `spicetify watch` crashes outside the Flatpak sandbox. Spotify is re-patched on every scheme change instead; restart it to see the new colours.
- A Spotify update undoes the patch until the next scheme change (or `spicetify apply` by hand).

## Vesktop (`home/apps/vesktop.nix`)

- caelestia writes `~/.config/vesktop/themes/caelestia.theme.css` on every scheme change, but Vencord never enables a theme just because it exists — turn it on once in Vesktop's Settings > Themes. Until then Vesktop runs unthemed with no hint why.

## VSCodium (`home/apps/vscodium.nix`)

- The dots' theme extension is installed once from its `.vsix` and then left alone, so it can keep regenerating its own theme file. To move to a new extension version, delete `~/.vscode-oss/extensions/soramanew.caelestia-vscode-integration-*` so it reinstalls.

## Zen (`home/apps/zen.nix`)

- Colours come from CaelestiaZen, a community Sine mod — not caelestia's CaelestiaFox extension, which is Firefox-only (upstream marks Zen theming won't-fix). If CaelestiaFox is installed in Zen, it does nothing and can be removed.
- After the first deploy, restart Zen once: Sine's loader is part of the Zen package, so an already-running Zen doesn't have it. From then on it follows every scheme change live.
- Text colour follows Zen's own light/dark setting (Settings > Look and Feel), not the scheme. Forced dark is right for dark schemes but gives light-on-light text with a light one.
- `profiles.ini` is Nix-managed, so `zenProfilePath` has to match the profile directory Zen actually uses; a mismatch opens a new empty profile (the old one stays on disk).
- Sine and the mod don't self-update (disabled on purpose — their files are Nix-managed). Sine moves with the zen-browser flake input; CaelestiaZen is pinned by rev/hash and bumped by hand.

## Helium (`home/apps/helium.nix`)

- A Chrome theme generated from the scheme, loaded unpacked on every start, so Helium gets caelestia's exact surface colours. (Not caelestia's own Chromium approach, the `BrowserThemeColor` policy: Chrome clamps policy themes to a mid-tone frame no matter how dark the seed.)
- Not live: Chrome reads themes only at startup, so a scheme change shows on Helium's next start. Accents (focus rings, buttons) stay Chrome's blue — themes have no slot for them.
- The first start after deploying shows an "Installed theme Caelestia" bar once; don't click Undo. Any policy that sets a theme colour would block this theme ("blocked by the administrator"), which is why caelestia's `enableChromium` is off.

## ZapZap (`home/apps/zapzap.nix`)

- WhatsApp Web: the `zapzap.css` template, linked into ZapZap's global customizations folder (`~/.local/share/ZapZap/customizations/global/css/caelestia.css`) and switched on in `ZapZap.conf` on every activation. It overrides WhatsApp's `--WDS-*` colour variables (list from Catppuccin's WhatsApp Web userstyle, mapped onto caelestia's Material roles).
- ZapZap's own window (menu bar, dialogs): ZapZap hardcodes its Qt palette, so the package is patched to overlay it with the rendered `zapzap-qt.json`. That means it builds locally instead of coming from the binary cache.
- Not live: both are read when ZapZap starts (the CSS also on a page reload, Ctrl+R). The logged-out QR/landing page keeps WhatsApp's cream background — it's hardcoded there, not a variable.
- Removing `caelestia.css` in ZapZap's Customizations settings only lasts until the next rebuild re-links it; disabling it there (the per-file toggle) sticks.

## Steam (`gaming/steam.nix`)

- Millennium (Steam client modding) plus the Material theme with its Matugen colour option, fed by the `steam-material.css` template. Colours and light/dark follow scheme changes live — the theme re-reads its colour file every 1.5s.
- First launch after deploying: Millennium may show its welcome dialog once. The active theme and colour option are set in `~/.config/millennium/config.json` on every activation, so picking another theme in Millennium only lasts until the next rebuild.
- Millennium hooks in by symlinking `~/.local/share/Steam/ubuntu12_{32,64}/libXtst.so.6` on every Steam launch. If it's ever removed from `gaming/steam.nix`, delete those two symlinks by hand, or Steam keeps trying to load a library that's gone.
- Millennium and the theme are pinned (flake input URL; rev + hash in `gaming/steam.nix`) with their in-app update checks off — bump them there. The v3.5.0 pin carries a one-line hash fix for upstream's packaging, which stops matching (and can be removed) once the pin moves past SteamClientHomebrew/Millennium#907.
