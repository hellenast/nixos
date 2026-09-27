{ pkgs, lib, inputs, ... }:

# VSCodium with the caelestia dots' settings and the dots' theme extension
# (caelestia-vscode-integration), which generates a "Caelestia" colour theme
# from the current scheme.
let
  dots = inputs.caelestia-dots-src;

  # The extension ships as a versioned .vsix in the dots repo. Found by
  # suffix so a new version doesn't need a hand-edited name, and the
  # installed extension's directory name is derived from it.
  vscodeIntegrationDir = "${dots}/vscode/caelestia-vscode-integration";
  vscodeIntegrationVsixName = lib.findFirst (n: lib.hasSuffix ".vsix" n) null (builtins.attrNames (builtins.readDir vscodeIntegrationDir));
  vscodeIntegrationVsix = "${vscodeIntegrationDir}/${vscodeIntegrationVsixName}";
  vscodeIntegrationExtensionDir = "soramanew.${lib.removeSuffix ".vsix" vscodeIntegrationVsixName}";

  # Regenerates the extension's themes/caelestia.json from the current
  # scheme with the extension's own generator (out/theme.js), exactly as its
  # activate() does. The extension itself only does that once VSCodium has
  # started, after the window was already painted from the old file, so the
  # first launch after a scheme change showed stale colours. Running this
  # before every launch (wrapper below) and on every scheme change
  # (postHooks) keeps the file current before VSCodium reads it.
  vscodeThemeSync = pkgs.writeShellScript "caelestia-vscode-theme-sync" ''
    ext="$HOME/.vscode-oss/extensions/${vscodeIntegrationExtensionDir}"
    scheme="''${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/scheme.json"
    [ -f "$ext/out/theme.js" ] && [ -f "$scheme" ] || exit 0
    ${pkgs.nodejs}/bin/node -e '
      const fs = require("fs"), path = require("path");
      const [ext, schemePath] = process.argv.slice(1);
      const mod = require(path.join(ext, "out", "theme.js"));
      const scheme = JSON.parse(fs.readFileSync(schemePath, "utf8"));
      const colours = Object.fromEntries(Object.entries(scheme.colours).map(([n, c]) => [n, "#" + c]));
      const out = JSON.stringify((mod.default || mod)(colours));
      const file = path.join(ext, "themes", "caelestia.json");
      // Only write on change: the theme file is watched while VSCodium runs.
      if (!fs.existsSync(file) || fs.readFileSync(file, "utf8") !== out) fs.writeFileSync(file, out);
    ' "$ext" "$scheme" || true
  '';

  # VSCodium with the theme synced right before every launch. Its .desktop
  # entry runs plain `codium`, so launcher starts are covered too.
  vscodiumCaelestia = pkgs.symlinkJoin {
    name = "vscodium-caelestia";
    paths = [ pkgs.vscodium ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = "wrapProgram $out/bin/codium --run ${vscodeThemeSync}";
  };
in
{
  home.packages = [ vscodiumCaelestia ];

  # The dots' settings already select the "Caelestia" colour theme, so
  # there's nothing to pick by hand once the extension is installed.
  xdg.configFile."VSCodium/User/settings.json".source = "${dots}/vscode/settings.json";
  xdg.configFile."VSCodium/User/keybindings.json".source = "${dots}/vscode/keybindings.json";
  xdg.configFile."codium-flags.conf".source = "${dots}/vscode/flags.conf";

  caelestia.postHooks = [ "${vscodeThemeSync}" ];

  # Installs the extension only if it isn't there yet.
  # `codium --install-extension` with a local .vsix always reinstalls,
  # wiping the extension's generated themes/caelestia.json on every rebuild.
  # A version bump therefore means deleting
  # ~/.vscode-oss/extensions/soramanew.caelestia-vscode-integration-* by
  # hand so it reinstalls.
  home.activation.caelestiaVscodeIntegration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.vscode-oss/extensions/${vscodeIntegrationExtensionDir}" ]; then
      $DRY_RUN_CMD ${pkgs.vscodium}/bin/codium $VERBOSE_ARG --install-extension "${vscodeIntegrationVsix}" || true
    fi
  '';
}
