# Gaming

Modules: `modules/gaming/`. The Steam client's caelestia theme is covered in [theming.md](theming.md#steam-gamingsteamnix).

## GameMode (`steam.nix`)

- Applies automatically to anything launched through Steam. For anything else, add `gamemoderun %command%` to the game's launch options.

## The NVIDIA laptop (`system/gpu.nix`)

- On `hyena-lt-work`, games run on the AMD integrated graphics unless offloaded to the NVIDIA GPU: set a Steam game's launch options to `nvidia-offload %command%` (with GameMode too: `nvidia-offload gamemoderun %command%`), and start anything else with `nvidia-offload <command>`. See [machines.md](machines.md#nvidia-hyena-lt-work).

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

## CrossMacro and Roblox anti-AFK (`crossmacro.nix`)

[CrossMacro](https://github.com/alper-han/CrossMacro) is a GUI macro recorder/player and autoclicker that works on Wayland: record mouse/keyboard input or build a macro in its editor, then replay it with loops, delays, global hotkeys or a schedule. Open it from the app launcher ("CrossMacro").

- **Log out and back in (or reboot) after the first deploy.** Input goes through `crossmacro.service`, a daemon only `crossmacro` group members can use, and the group only applies to new logins. `crossmacro doctor --verbose` shows what's working if input doesn't.
- Macros, settings, hotkeys and schedules made in the app are its own (in `~/.config/crossmacro`), not managed by Nix.
- Its default global hotkeys while it's open are F8 (record), F9 (play) and F10 (pause). F9 is also Roblox's developer console, so change them in its Settings if that gets in the way.
- Like any Wayland input tool, it sends input to whichever window is focused.

### Roblox anti-AFK

Roblox disconnects players after 20 minutes without input. **Super+Alt+A** (or "Roblox Anti-AFK" in the launcher) turns on a loop that presses Space (a jump) every 2 minutes; press it again to turn it off. A notification confirms each change.

- It only presses the key while Roblox is the focused window and the screen isn't locked, so it never types into another app. **Leave Roblox focused** when going AFK.
- The simulated key counts as activity, so the screen won't lock or turn off while it's running with Roblox focused. (A lock screen would take the keyboard away from Roblox.)
- It turns itself off when Roblox closes, or if CrossMacro can't send input (the notification says why; usually the log-out step above).
- The key and interval are `antiAfkKey`/`antiAfkInterval` at the top of `modules/gaming/crossmacro.nix`. Keep the interval under caelestia's 3-minute lock timeout.
- It runs as the `roblox-anti-afk` user service: `journalctl --user -u roblox-anti-afk` for its log.

## Razer Tartarus Pro / Input Remapper (`input-remapper.nix`)

[Input Remapper](https://github.com/sezanzeb/input-remapper) changes what each key of one specific device does, so the keypad can be remapped without touching the regular keyboard. Open it from the app launcher ("Input Remapper"). It asks for your password when it opens, to read the devices.

1. Pick **Razer Razer Tartarus Pro** in the device list and create a preset. Make one per game if they need different layouts.
2. Add a mapping, click **Record** and press the keypad key, then type what it should send: a key (`a`, `F13`), a combination (`Control_L + c`), a mouse button (`BTN_LEFT`) or a macro (e.g. `key(1).wait(50).key(2)`). The output field autocompletes names.
3. **Apply** to start using it, and turn on **Autoload** so it's applied at every login and whenever the keypad is plugged in.

- One preset per device is active at a time. Switch presets in the app.
- Keys without a mapping keep doing what they did. Without any preset, the keypad sends the ordinary keyboard keys it's set to from the factory.
- Mapped keys still go through the keyboard layout, which is US international. A key mapped to `'`, `` ` ``, `"`, `~` or `^` is a dead key, the same as typing it on the keyboard.
- Presets live in `~/.config/input-remapper-2`, not managed by Nix.
- The keypad's Razer-specific features (lighting, analog actuation depth, its onboard profiles) are set by Razer's own software or OpenRazer, not by Input Remapper. Here its keys are plain on/off keys.
- If a preset stops applying, for example after a rebuild that restarted the daemon, run "input-remapper-autoload" from the launcher. Logs: `journalctl -u input-remapper` for the daemon, `journalctl --user -u input-remapper-autoload` for the login step.

## Trainers (`trainers.nix`)

The `trainer` command runs Windows trainers (Cheat Happens, FLiNG, Cheat Engine, any standalone `.exe`) inside a Steam game's own Proton session. A trainer started any other way can't find the game, because it's in a separate Wine session.

1. In Steam, open the game's **Properties → General → Launch Options** and set them to `trainer %command%`. If you already have options there, put `trainer` first, e.g. `trainer gamemoderun %command%`.
2. Launch the game once. That creates its folder, `~/Games/Trainers/<game name as Steam shows it>/`.
3. Put the trainer's `.exe` in that folder (unzip it first if it came zipped). From the next launch on, the trainer starts with the game, and a notification confirms it.

- Only one `.exe` can be in the folder, or nothing starts and a notification says why. Keep extra files (READMEs, DLLs the trainer needs) next to it.
- `trainer run <exe>` starts a trainer by hand in the running game, still only for games launched with `trainer %command%`. Add the Steam app id after it if more than one is running. `trainer list` shows the running games it can reach.
- The trainer's output goes to `~/.local/state/trainer/<app id>.log`.
- Close the trainer when you quit the game. While it's open, Steam may still show the game as running.
- Only Proton games are supported; native Linux games don't run Wine for a trainer to join.
- WeMod/Wand isn't covered. It's a full app that needs .NET installed in every game's prefix, not a standalone trainer.

How it works: with `STEAM_COMPAT_LAUNCHER_SERVICE=proton` set (which `trainer %command%` does), Proton starts the game through a launcher service on the session bus, `com.steampowered.App<app id>`. The Steam Linux Runtime's `steam-runtime-launch-client --inside-app=<app id>` runs commands through that service in the game's Proton environment, with its prefix and its `wine`.

## VR headset / ALVR (`vr.nix`)

- Headset pairing — installing the ALVR client on the headset and connecting it to this PC — is done once per headset, outside Nix.
- SteamVR itself is installed and configured through Steam.
