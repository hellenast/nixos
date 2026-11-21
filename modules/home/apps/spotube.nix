{ lib, pkgs, ... }:

# Spotube (open-source music client: metadata, audio, lyrics and scrobbling
# all through plugins), following the caelestia scheme.
#
# Spotube 6 has no custom colours: its "Millennium" UI offers three palettes
# (Blue, Orange, Lime), each with fixed surfaces, and it's a prebuilt
# GraalVM native image with nothing to inject a theme into. So the scheme's
# colours are patched into a copy of the binary instead (like spicetify does
# for Spotify), and that copy is what runs. Light/dark follows live; the
# colours themselves show on the next launch.
let
  # nixpkgs still has Spotube 5, whose package is built around 5's Flutter
  # .deb. 6 is a Compose Multiplatform rewrite: a native image that unpacks
  # its own JNI libraries (window, webview, tray, media keys...) into
  # ~/.cache/nucleus at runtime and dlopens the rest, so everything those
  # need goes on LD_LIBRARY_PATH rather than just into RPATHs. libvlc plays
  # the audio; it's only bundled in the AppImage.
  spotubeVersion = "6.0.0";

  spotubeLibs = with pkgs; [
    alsa-lib
    cairo
    dbus
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    hunspell
    libGL
    libgbm
    libsoup_3
    libvlc
    libx11
    libxext
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
    pango
    stdenv.cc.cc.lib
    systemdLibs
    wayland
    webkitgtk_4_1
    zlib
  ];

  # SPOTUBE_EXECUTABLE, if set, runs that build of the binary (a patched
  # copy, below) instead, with this package's environment. The copy needs
  # the files next to share/spotube/spotube beside it.
  spotube =
    lib.warnIf (lib.versionAtLeast pkgs.spotube.version spotubeVersion)
      "spotube.nix: nixpkgs has Spotube ${pkgs.spotube.version} now, the local package can go"
      (pkgs.stdenv.mkDerivation {
        pname = "spotube";
        version = spotubeVersion;

        src = pkgs.fetchurl {
          url = "https://github.com/team-spotube/spotube/releases/download/v${spotubeVersion}/spotube-linux-${spotubeVersion}-x86_64.tar.xz";
          hash = "sha256-Rg70TPUN5jjo7Nr1p/rRvH+Bzy3Sdth5Tuo0FyZZXn0=";
        };

        nativeBuildInputs = with pkgs; [
          autoPatchelfHook
          makeWrapper
          wrapGAppsHook3
        ];

        buildInputs = spotubeLibs ++ [ pkgs.glib-networking ];

        dontWrapGApps = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out/share/spotube
          cp -r app/. $out/share/spotube/
          cp -r share/. $out/share/
          runHook postInstall
        '';

        postFixup = ''
          makeShellWrapper $out/share/spotube/spotube $out/bin/spotube \
            "''${gappsWrapperArgs[@]}" \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath spotubeLibs} \
            --run 'if [ -n "''${SPOTUBE_EXECUTABLE-}" ]; then exe=$SPOTUBE_EXECUTABLE; unset SPOTUBE_EXECUTABLE; exec "$exe" "$@"; fi'
        '';

        meta = {
          description = "Open source music client with plugin-based metadata and audio sources";
          homepage = "https://spotube.cc";
          license = lib.licenses.agpl3Plus;
          mainProgram = "spotube";
          platforms = [ "x86_64-linux" ];
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        };
      });

  # Where each palette's colours sit in the binary. Every palette is a
  # MillenniumColors built in one stretch of code: each colour loaded as a
  # 64-bit immediate (Compose's packed Color, ARGB << 32), then stored into
  # its field. The immediates are what gets patched. A few fields are filled
  # from Color.White, a static, instead; those can't be patched without
  # changing every white in the app, and are left out.
  #
  # Fails the build unless every palette is found exactly once holding its
  # stock colours, so a Spotube update that moves things can't go unnoticed
  # (update STOCK from millennium's theme/Theme.kt with it).
  spotubePaletteLocator = pkgs.writers.writePython3 "spotube-palette-locator" { flakeIgnore = [ "E501" ]; } ''
    import json
    import struct
    import sys

    # MillenniumColors' fields, in the order of their slots (+0x8, +0x10,
    # ...) in the native image's object layout.
    FIELDS = [
        "background", "surface", "raised", "inset", "text", "muted", "border", "highlight",
        "accent", "accentTop", "accentBottom", "onAccent", "success", "danger", "scrim",
    ]

    W = 0xFFFFFFFF
    # The six role sets as millennium 0.1.1 (Spotube 6.0.0's) defines them.
    STOCK = {
        ("Blue", "light"): [0xFFE4EDF3, 0xFFF4F8FB, W, 0xFFDCE6ED, 0xFF172C42, 0xFF4A6075, 0xFF98ADBF, W, 0xFF005CB9, 0xFF1675B8, 0xFF003B91, W, 0xFF257B51, 0xFFBC334A, 0x99101E30],
        ("Blue", "dark"): [0xFF09090B, 0xFF18181B, 0xFF27272A, 0xFF111113, 0xFFFAFAFA, 0xFFA1A1AA, 0xFF3F3F46, 0xFF71717A, 0xFF79CFFF, 0xFF1976B9, 0xFF002D74, W, 0xFF7AE2AE, 0xFFFF98A9, 0xBB030912],
        ("Orange", "light"): [0xFFFAFAFA, W, W, 0xFFF4F4F5, 0xFF27272A, 0xFF52525B, 0xFFD4D4D8, W, 0xFF9A3412, 0xFFFDBA74, 0xFFD97706, 0xFF431407, 0xFF166534, 0xFFB42332, 0x990F0906],
        ("Orange", "dark"): [0xFF09090B, 0xFF18181B, 0xFF27272A, 0xFF111113, 0xFFFAFAFA, 0xFFA1A1AA, 0xFF3F3F46, 0xFF71717A, 0xFFFB923C, 0xFFFDBA74, 0xFFF97316, 0xFF431407, 0xFF86EFAC, 0xFFFF8A80, 0xCC050505],
        ("Lime", "light"): [0xFFFAFAFA, W, W, 0xFFF4F4F5, 0xFF27272A, 0xFF52525B, 0xFFD4D4D8, W, 0xFF3F6212, 0xFFBEF264, 0xFF84CC16, 0xFF1A2E05, 0xFF3F6212, 0xFFB42332, 0x99080A06],
        ("Lime", "dark"): [0xFF09090B, 0xFF18181B, 0xFF27272A, 0xFF111113, 0xFFFAFAFA, 0xFFA1A1AA, 0xFF3F3F46, 0xFF71717A, 0xFFA3E635, 0xFFBEF264, 0xFF84CC16, 0xFF1A2E05, 0xFFA3E635, 0xFFFF8A80, 0xCC050505],
    }

    data = open(sys.argv[1], "rb").read()


    def decode(i):
        """The three instruction forms the constructors are built from, or None."""
        rex, op = data[i], data[i + 1]
        # movabs r64, imm64
        if rex in (0x48, 0x49) and 0xB8 <= op <= 0xBF:
            return "imm", op - 0xB8 + (rex & 1) * 8, i + 2, i + 10
        modrm = data[i + 2]
        # mov QWORD PTR [base+disp8], r64
        if rex in (0x48, 0x49, 0x4C, 0x4D) and op == 0x89 and modrm >> 6 == 1 and modrm & 7 != 4:
            return "store", (modrm >> 3 & 7) + (rex >> 2 & 1) * 8, ((modrm & 7) + (rex & 1) * 8, data[i + 3]), i + 4
        # mov r64, QWORD PTR [rsp+disp8]: a value spilled earlier (Color.White)
        if rex in (0x48, 0x4C) and op == 0x8B and modrm >> 6 == 1 and modrm & 7 == 4 and data[i + 3] == 0x24:
            return "spill", (modrm >> 3 & 7) + (rex >> 2 & 1) * 8, None, i + 5
        return None


    def constructor_at(start):
        """The field stores of a MillenniumColors starting at start, as {field: immediate's offset or None}."""
        regs, fields, base, i = {}, {}, None, start
        while len(fields) < len(FIELDS):
            insn = decode(i)
            if not insn:
                return None
            kind, reg, arg, i = insn
            if kind != "store":
                regs[reg] = arg
                continue
            if reg not in regs or (base is not None and arg[0] != base) or arg[1] % 8 or not 8 <= arg[1] <= 8 * len(FIELDS):
                return None
            base = arg[0]
            fields[FIELDS[arg[1] // 8 - 1]] = regs[reg]
        return fields


    found = {}
    for key, stock in STOCK.items():
        accent = struct.pack("<Q", stock[FIELDS.index("accent")] << 32)
        hits = []
        at = data.find(accent)
        while at != -1:
            for start in range(max(at - 0x100, 0), at - 1):
                fields = constructor_at(start)
                if fields and fields["accent"] == at:
                    hits.append(fields)
                    break
            at = data.find(accent, at + 1)
        if len(hits) != 1:
            sys.exit(f"spotube palette locator: {key}: expected one constructor, found {len(hits)}")
        for field, offset in hits[0].items():
            if offset is not None and struct.unpack_from("<Q", data, offset)[0] != stock[FIELDS.index(field)] << 32:
                sys.exit(f"spotube palette locator: {key}: {field} isn't the stock colour")
        # Immediate's offset -> the fields it feeds (a register can feed several).
        slots = {}
        for field in FIELDS:
            if hits[0][field] is not None:
                slots.setdefault(hits[0][field], []).append(field)
        found.setdefault(key[0], {})[key[1]] = sorted(slots.items())

    json.dump(found, sys.stdout)
  '';

  spotubePalettes = pkgs.runCommand "spotube-palettes.json" { } ''
    ${spotubePaletteLocator} ${spotube}/share/spotube/spotube > $out
  '';

  # Right before every launch: makes (or reuses) a copy of Spotube's binary
  # with the scheme's colours patched into all three palettes for the
  # scheme's mode, and prints its path. Also selects the palette whose every
  # slot that matters could be patched, and the "System" theme mode, in
  # Spotube's settings.
  #
  # Light/dark itself needs no syncing: in "System" mode Spotube follows the
  # XDG portal's color-scheme, which caelestia sets on every scheme change.
  # A switch while Spotube runs shows that mode's stock palette until the
  # next launch, though: the scheme only has its own mode's colours.
  #
  # The copy lives in ~/.cache/caelestia/spotube, with everything else from
  # the package linked in beside it. On btrfs it's a reflink, so it takes
  # next to no space; it's only redone when the scheme or the package
  # changes.
  #
  # Spotube reads its settings once at startup, so they're written before
  # launch too, but only once Spotube has created them on its first start:
  # creating the file first would make Spotube take the start for an
  # upgrade and skip its onboarding. That first start is already patched,
  # just on the default palette, Blue.
  spotubeThemeSync = pkgs.writers.writePython3 "caelestia-spotube-theme-sync" { flakeIgnore = [ "E501" ]; } ''
    import fcntl
    import json
    import os
    import shutil
    import struct
    import subprocess
    import sys

    app_dir, palettes_file = sys.argv[1:3]

    # The palette selected for each mode: the ones whose unpatchable slots
    # (Color.White) are ones that are white in that mode anyway, or none.
    PALETTE = {"dark": "Orange", "light": "Blue"}

    # Scheme colour for each MillenniumColors role. Millennium's light
    # surfaces are lighter than its background and its dark ones darker, so
    # the two modes take their containers in opposite orders.
    ROLES = {
        "background": {"dark": "surface", "light": "surfaceContainer"},
        "surface": {"dark": "surfaceContainer", "light": "surface"},
        "raised": {"dark": "surfaceContainerHighest", "light": "surfaceContainerLowest"},
        "inset": {"dark": "surfaceContainerLow", "light": "surfaceContainerHigh"},
        "text": "onSurface",
        "muted": "onSurfaceVariant",
        "border": "outlineVariant",
        "highlight": "outline",
        "accent": "primary",
        "accentTop": "primary",
        "accentBottom": "primaryDim",
        "onAccent": "onPrimary",
        "success": "success",
        "danger": "error",
        "scrim": "scrim",
    }
    # Most of caelestia's static schemes have no primaryDim.
    FALLBACK = {"primaryDim": "primary"}
    # Millennium's own scrim opacity.
    SCRIM_ALPHA = {"dark": 0xCC, "light": 0x99}


    def argb(colours, mode, role):
        name = ROLES[role] if isinstance(ROLES[role], str) else ROLES[role][mode]
        rgb = int(colours.get(name) or colours[FALLBACK[name]], 16)
        return (SCRIM_ALPHA[mode] if role == "scrim" else 0xFF) << 24 | rgb


    def patched_binary(colours, mode):
        with open(palettes_file) as f:
            palettes = json.load(f)
        values = {
            offset: argb(colours, mode, roles[0])
            for sets in palettes.values()
            for offset, roles in sets[mode]
        }
        stamp = json.dumps({"source": os.path.realpath(app_dir), "values": values})

        cache = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
        root = os.path.join(cache, "caelestia", "spotube")
        os.makedirs(os.path.dirname(root), exist_ok=True)
        with open(root + ".lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                with open(os.path.join(root, "stamp")) as f:
                    if f.read() == stamp:
                        return os.path.join(root, "spotube")
            except OSError:
                pass

            new = root + ".new"
            shutil.rmtree(new, ignore_errors=True)
            os.mkdir(new)
            # The native image finds its JDK libraries next to itself.
            for name in os.listdir(app_dir):
                if name != "spotube":
                    os.symlink(os.path.join(app_dir, name), os.path.join(new, name))
            binary = os.path.join(new, "spotube")
            subprocess.run(["${pkgs.coreutils}/bin/cp", "--reflink=auto", os.path.join(app_dir, "spotube"), binary], check=True)
            os.chmod(binary, 0o755)
            with open(binary, "r+b") as f:
                for offset, value in values.items():
                    f.seek(offset)
                    f.write(struct.pack("<Q", value << 32))
            with open(os.path.join(new, "stamp"), "w") as f:
                f.write(stamp)

            # A Spotube still running keeps its (by then unlinked) copy.
            old = root + ".old"
            shutil.rmtree(old, ignore_errors=True)
            if os.path.exists(root):
                os.rename(root, old)
            os.rename(new, root)
            shutil.rmtree(old, ignore_errors=True)
            return os.path.join(root, "spotube")


    # The settings file is an androidx DataStore preferences file: a protobuf
    # map (field 1, one entry per key) of key (1) to a typed value (2), with
    # UserSettings stored as a JSON string (value field 5) under
    # "user_settings". Every field at the levels walked here is
    # length-delimited.
    def read_varint(buf, i):
        value = shift = 0
        while True:
            byte = buf[i]
            i += 1
            value |= (byte & 0x7F) << shift
            if byte < 0x80:
                return value, i
            shift += 7


    def varint(value):
        out = bytearray()
        while value >= 0x80:
            out.append(value & 0x7F | 0x80)
            value >>= 7
        out.append(value)
        return bytes(out)


    def fields(buf):
        i = 0
        while i < len(buf):
            tag, i = read_varint(buf, i)
            size, i = read_varint(buf, i)
            if tag & 7 != 2 or i + size > len(buf):
                raise ValueError("unexpected protobuf layout")
            yield tag >> 3, buf[i:i + size]
            i += size


    def field(number, payload):
        return varint(number << 3 | 2) + varint(len(payload)) + payload


    def select_palette(palette):
        data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        store = os.path.join(data, "Spotube", "spotube.preferences_pb")
        with open(store, "rb") as f:
            entries = list(fields(f.read()))
        # Missing fields decode to their defaults, so a file without
        # "user_settings" yet just gets one holding these two.
        settings, at = {}, len(entries)
        for i, (number, entry) in enumerate(entries):
            parts = dict(fields(entry))
            if number == 1 and parts.get(1) == b"user_settings":
                settings, at = json.loads(dict(fields(parts[2]))[5]), i
                break

        wanted = {"theme": "SYSTEM", "palette": palette}
        if all(settings.get(k) == v for k, v in wanted.items()):
            return
        settings.update(wanted)
        value = field(5, json.dumps(settings, ensure_ascii=False, separators=(",", ":")).encode())
        entries[at:at + 1] = [(1, field(1, b"user_settings") + field(2, value))]
        with open(store + ".caelestia", "wb") as f:
            f.write(b"".join(field(n, e) for n, e in entries))
        os.replace(store + ".caelestia", store)


    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    try:
        with open(os.path.join(state, "caelestia", "scheme.json")) as f:
            scheme = json.load(f)
        colours, mode = scheme["colours"], scheme["mode"]
    except (OSError, ValueError, KeyError):
        sys.exit(0)
    if mode not in PALETTE:
        sys.exit(0)

    try:
        print(patched_binary(colours, mode))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError):
        pass
    try:
        select_palette(PALETTE[mode])
    except (OSError, ValueError, KeyError, IndexError):
        pass
  '';

  # Spotube running the patched copy, synced right before every launch. Its
  # .desktop entry runs plain `spotube`, so launcher starts are covered too.
  # A failed sync prints nothing, and the stock binary runs.
  spotubeCaelestia = pkgs.symlinkJoin {
    name = "spotube-caelestia";
    paths = [ spotube ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/spotube \
        --run 'export SPOTUBE_EXECUTABLE="$(${spotubeThemeSync} ${spotube}/share/spotube ${spotubePalettes} || true)"'
    '';
  };
in
{
  home.packages = [ spotubeCaelestia ];
}
