{ pkgs, inputs, ... }:

# Minecraft, both editions. Sign-in and game downloads happen inside the
# launchers on first use — see docs/gaming.md.
{
  environment.systemPackages = [
    # Java Edition: Prism Launcher (FOSS, MultiMC-derived). Brings its own
    # JRE and per-instance mod loaders (Fabric/Forge/...), so no JDK needed.
    pkgs.prismlauncher

    # Bedrock Edition: bedrock-on-linux (flake input) runs the real Windows
    # (GDK) build under steam-run/Proton, with native Xbox sign-in. It ships
    # no game files; the first run downloads the game from Microsoft.
    # mcpelauncher and Waydroid were both tried first and both crash —
    # docs/gaming.md has the details, in case either gets fixed upstream.
    inputs.bedrock-on-linux.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
