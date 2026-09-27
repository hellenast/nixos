# Gaming

Modules: `modules/gaming/`. The Steam client's caelestia theme is covered in [theming.md](theming.md#steam-gamingsteamnix).

## GameMode (`steam.nix`)

- Applies automatically to anything launched through Steam. For anything else, add `gamemoderun %command%` to the game's launch options.

## Minecraft Java Edition (`minecraft.nix`)

- `prismlauncher` installs the launcher only. Signing in with a Microsoft account and creating/configuring instances (vanilla or modded, version + mod loader) happen inside it on first use.
- Instance data (worlds, mods, settings) lives in `~/.local/share/PrismLauncher` — covered by backing up `/home`.

## Minecraft Bedrock Edition (`minecraft.nix`)

[bedrock-on-linux](https://github.com/Wyze3306/BedrockOnLinux) runs the real Windows GDK build of Bedrock under steam-run/Proton, with native Xbox sign-in — no Android layer, no custom linker, just Proton as for any other Windows game. It ships no game files, so setup is interactive:

1. Launch `bedrock-on-linux` from the app menu.
2. Sign into a Microsoft account that owns Minecraft — twice: once for the Store download, once for Xbox Live (Friends/Realms/Marketplace). Achievements show in-game but don't unlock (a limitation of the tool).
3. The first run downloads the game from Microsoft under that account.

- If something breaks later (a Windows-side update, a crash), `bedrock-on-linux repair` rebuilds the Proton environment without touching worlds. Try that before reinstalling.
- `bedrock-on-linux doctor` runs a diagnostic if setup or launch fails.
- Data (Proton prefix, game, worlds, Xbox sign-in) lives in `~/.local/share/bedrock-on-linux` — covered by backing up `/home`.

### What didn't work

Two options tried and dropped first, in case either is fixed upstream:
- **mcpelauncher-ui-qt** (reimplements Android's dynamic linker to run Bedrock's native libraries on Linux): every Bedrock version tested segfaulted. Its custom symbol resolver lacks libc symbols current Bedrock builds call (`pthread_sigmask` — present in glibc itself per `nm`/`readelf`, so the gap is in mcpelauncher's shim).
- **Waydroid** ([virtualisation.md](virtualisation.md#waydroid-waydroidnix)): the container runs fine, but Bedrock crashes instantly with SIGSEGV in `libpairipcore.so`, Mojang's anti-tamper library, which appears to refuse to run in Waydroid's userdebug/test-keys LineageOS build. Confirmed on a from-scratch reinstall (new UID, new package path, same crash). Matches the open upstream report [waydroid/waydroid#2143](https://github.com/waydroid/waydroid/issues/2143), on unrelated Intel hardware, so it isn't specific to this machine's AMD GPU.

## Roblox (`roblox.nix`)

- Sober installs from Flathub and updates daily and on every boot. Sign into Roblox inside Sober on first launch.

## VR headset / ALVR (`vr.nix`)

- Headset pairing — installing the ALVR client on the headset and connecting it to this PC — is done once per headset, outside Nix.
- SteamVR itself is installed and configured through Steam.
