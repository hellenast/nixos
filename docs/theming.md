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

## Spotube (`home/apps/spotube.nix`)

- Spotube 6 has no custom colours (three fixed palettes), so the scheme's colours are patched into a copy of its binary in `~/.cache/caelestia/spotube`, and the `spotube` command runs that. On btrfs the copy is a reflink and takes next to no space. Delete the directory to drop it; the next launch makes it again.
- Not live: the copy is redone at launch when the scheme has changed, so a new scheme shows the next time Spotube starts. Light/dark does follow live (the theme mode is kept on "System"), but a switch while Spotube runs shows Spotube's stock palette for the new mode until it restarts.
- In light mode a few things stay plain white (raised buttons and cards): Spotube shares that white with the rest of the app, so it can't be patched on its own.
- The palette and theme mode are set in Spotube's settings at launch, so changing them there only lasts until the next launch. The very first start is on the default palette, where text on the accent stays white.
- A Spotube update that moves the colours makes the rebuild fail at `spotube-palettes.json`, rather than silently leaving Spotube unthemed. Its colour table comes from millennium's `theme/Theme.kt` and needs updating with it.
- Packaged in the module itself until nixpkgs moves past 5.x; a rebuild warns once it has.
- Spotube 6 doesn't carry anything over from 5: it starts over in `~/.local/share/Spotube` (plugins are a new kind too, so the Spotify one needs installing and logging into again). 5's data is left behind in `~/.local/share/oss.krtirtho.spotube`.

## Vesktop (`home/apps/vesktop.nix`)

- caelestia writes `~/.config/vesktop/themes/caelestia.theme.css` on every scheme change, but Vencord never enables a theme just because it exists — turn it on once in Vesktop's Settings > Themes. Until then Vesktop runs unthemed with no hint why.

## VSCodium (`home/apps/vscodium.nix`)

- The dots' theme extension is installed once from its `.vsix` and then left alone, so it can keep regenerating its own theme file. To move to a new extension version, delete `~/.vscode-oss/extensions/soramanew.caelestia-vscode-integration-*` so it reinstalls.

## Zen (`home/apps/zen.nix`)

- Colours come from CaelestiaZen, a community Sine mod that reads the scheme straight from `~/.local/state/caelestia/scheme.json` — not caelestia's CaelestiaFox extension, which is Firefox-only (upstream marks Zen theming won't-fix). If CaelestiaFox is installed in Zen, it does nothing and can be removed.
- Since 2.0 the mod also restyles Zen's interface (M3 Expressive: pill tabs, floating URL bar, FAB menu, ...). Its Sine settings switch that back to Zen's default look, or change shape and density. Website tinting is off (`caelestia.zen.tint` in `zen.nix`), so only the browser UI is themed.
- After the first deploy, restart Zen once: Sine's loader is part of the Zen package, so an already-running Zen doesn't have it. From then on it follows every scheme change live. After a CaelestiaZen bump, if the new version's look doesn't show up, `about:support` → **Clear Startup Cache** and restart.
- Light/dark follows the scheme: the mod switches Zen, and the light/dark preference websites see, whenever caelestia's mode changes. Turning off **Follow Caelestia light/dark** in its settings hands that back to Zen's own setting (Settings > Look and Feel).
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

## Beeper (`home/apps/beeper.nix`)

- Beeper's own custom CSS feature: the `beeper.css` template, linked in as `~/.config/BeeperTexts/custom.css`. Nothing to switch on — Beeper loads that file whenever it exists. It maps caelestia's Material roles onto Beeper's colour variables (and fixes the few places Beeper hardcodes white text on the accent).
- Not live: Beeper reads the file at startup, and on **Reload custom CSS** in its command bar (or **Reload CSS** next to the custom CSS settings). Light/dark does follow the desktop live, as long as Beeper's theme stays on **System** (its default).
- Leave Beeper's colour themes (the monochrome and gradient ones in its appearance settings) on the default: they paint their own tints and gradients over the scheme.
- Beeper's **Open CSS file in editor** edits the rendered file, which the next scheme change overwrites; changes belong in the template in `beeper.nix`. **Reset CSS** deletes the link, so Beeper runs unthemed until the next rebuild puts it back.
- The onboarding and login screens' illustrations are images and keep their own colours.

## Steam (`gaming/steam.nix`)

- Millennium (Steam client modding) plus the Material theme with its Matugen colour option, fed by the `steam-material.css` template. Colours and light/dark follow scheme changes live — the theme re-reads its colour file every 1.5s.
- First launch after deploying: Millennium may show its welcome dialog once. The active theme and colour option are set in `~/.config/millennium/config.json` on every activation, so picking another theme in Millennium only lasts until the next rebuild.
- Millennium hooks in by symlinking `~/.local/share/Steam/ubuntu12_{32,64}/libXtst.so.6` on every Steam launch. If it's ever removed from `gaming/steam.nix`, delete those two symlinks by hand, or Steam keeps trying to load a library that's gone.
- Millennium and the theme are pinned (flake input URL; rev + hash in `gaming/steam.nix`) with their in-app update checks off — bump them there. Millennium (v3.6.3) is built from its own flake's `packages` output against this system's nixpkgs; it handles both Steam's 32-bit client and the newer 64-bit one (`steamrt64`).
- The store's header bar (Browse, Recommendations, ..., search) is recoloured by a few extra rules appended to the theme's `store.css` in `gaming/steam.nix` — the theme leaves it Steam-blue. They target Steam's hashed class names, which change when Steam rebuilds its store: if the bar turns blue again, those names need refreshing (the header renders into `[data-featuretarget="store-menu-v7"]`).
