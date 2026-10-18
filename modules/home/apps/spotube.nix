{ pkgs, ... }:

# Spotube (open-source music client: metadata through plugins, audio from
# YouTube and others), following the caelestia scheme as far as it can.
#
# Spotube 5 has no custom colours. Its accent setting only picks one of
# shadcn_flutter's twelve built-in colour schemes by name (colorSchemeMap in
# lib/modules/settings/color_scheme_picker_dialog.dart), each with its own
# fixed backgrounds, and the app is a prebuilt Flutter binary, so there's
# nothing to inject a theme into. What follows the scheme: the accent, as
# the preset nearest the scheme's primary, and light/dark. Neither is live.
let
  # Writes the preset nearest the scheme's primary, and the scheme's
  # light/dark mode, into Spotube's preferences (row 0 of preferences_table
  # in its drift database). Nearest is measured in OKLab: by hue among the
  # coloured presets, or by tint among the greys when the primary is nearly
  # grey (monochrome-style schemes).
  #
  # The mode is set explicitly rather than left on Spotube's "System":
  # that came up light under a dark scheme here, even with GSettings'
  # color-scheme at prefer-dark.
  #
  # Spotube reads these once at startup (an outside write doesn't reach its
  # drift streams), so this runs right before every launch (wrapper below)
  # instead of on scheme changes. It does nothing until Spotube has created
  # its database on its first start, so that one start is unthemed.
  spotubeThemeSync = pkgs.writers.writePython3 "caelestia-spotube-theme-sync" { flakeIgnore = [ "E501" ]; } ''
    import json
    import math
    import os
    import sqlite3
    import sys

    # Shade 500 of each preset (shadcn_flutter's Colors.<name>), the value
    # Spotube's own picker stores next to the name. Only the name selects the
    # scheme; the value is kept accurate so the picker shows the right swatch.
    PRESETS = {
        "slate": "64748b",
        "gray": "6b7280",
        "zinc": "71717a",
        "neutral": "737373",
        "stone": "78716c",
        "red": "ef4444",
        "orange": "f97316",
        "yellow": "eab308",
        "green": "22c55e",
        "blue": "3b82f6",
        "violet": "8b5cf6",
        "rose": "f43f5e",
    }
    # Greys, tinted blue to warm.
    GREYS = ["slate", "gray", "zinc", "neutral", "stone"]


    def oklab(hex_colour):
        def linear(c):
            c /= 255
            return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

        r, g, b = (linear(int(hex_colour[i:i + 2], 16)) for i in (0, 2, 4))
        lc = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
        mc = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
        sc = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
        return (
            1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc,
            0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc,
        )


    def nearest(primary):
        a, b = oklab(primary)
        if math.hypot(a, b) < 0.04:
            return min(GREYS, key=lambda n: math.dist((a, b), oklab(PRESETS[n])))
        hue = math.atan2(b, a)

        def hue_gap(name):
            pa, pb = oklab(PRESETS[name])
            gap = abs(hue - math.atan2(pb, pa)) % math.tau
            return min(gap, math.tau - gap)

        return min((n for n in PRESETS if n not in GREYS), key=hue_gap)


    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    db = os.path.join(data, "oss.krtirtho.spotube", "db.sqlite")
    try:
        with open(os.path.join(state, "caelestia", "scheme.json")) as f:
            scheme = json.load(f)
        primary = scheme["colours"]["primary"]
        mode = scheme["mode"]
    except (OSError, ValueError, KeyError):
        sys.exit(0)
    if mode not in ("light", "dark") or not os.path.exists(db):
        sys.exit(0)

    name = nearest(primary)
    # Same "name:ARGB" (decimal) format as SpotubeColor.toString().
    accent = f"{name}:{0xff000000 | int(PRESETS[name], 16)}"
    try:
        con = sqlite3.connect(db, timeout=5)
        with con:
            con.execute(
                "UPDATE preferences_table SET accent_color_scheme = ?, theme_mode = ?"
                " WHERE id = 0 AND (accent_color_scheme != ? OR theme_mode != ?)",
                (accent, mode, accent, mode),
            )
        con.close()
    except sqlite3.Error:
        pass
  '';

  # Spotube with the theme synced right before every launch. Its .desktop
  # entry runs plain `spotube`, so launcher starts are covered too. `|| true`
  # because the wrapper runs under `set -e`: a failed sync must never stop
  # Spotube from starting.
  spotubeCaelestia = pkgs.symlinkJoin {
    name = "spotube-caelestia";
    paths = [ pkgs.spotube ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = "wrapProgram $out/bin/spotube --run '${spotubeThemeSync} || true'";
  };
in
{
  home.packages = [ spotubeCaelestia ];
}
