{ config, pkgs, lib, username, ... }:

let
  # huami-token: one-off CLI to pull the Bluetooth pairing auth key for my
  # GTR2e from Huami/Zepp's servers (Xiaomi/Amazfit account login), which
  # Amazfish needs to actually pair with the watch. I run it by hand
  # (`huami-token`) when (re)pairing — it's not something that runs on its
  # own.
  huami-token = pkgs.python3.pkgs.buildPythonApplication rec {
    pname = "huami-token";
    version = "0.8.0";
    pyproject = true;

    # Pinned to a specific commit so the build is reproducible — a full
    # commit hash in `rev` is what makes this valid under flakes' pure
    # evaluation, no separate sha256/hash needed.
    src = builtins.fetchGit {
      url = "https://github.com/argrento/huami-token.git";
      rev = "1b32658519d1f35cd3c4345bb9ced3ba6881bb56";
    };

    build-system = with pkgs.python3.pkgs; [
      hatchling  # this project's Python build backend (pyproject.toml)
    ];

    dependencies = with pkgs.python3.pkgs; [
      loguru        # structured logging, used for the tool's own status/debug output
      pycryptodome  # crypto primitives for the encrypted Zepp login payload
      requests      # HTTP client for talking to Huami/Zepp's servers
    ];

    # The test suite needs real Xiaomi/Amazfit account credentials to run —
    # skipping for this packaging.
    doCheck = false;

    meta = with lib; {
      description = "Retrieve the Bluetooth pairing auth key for Xiaomi/Amazfit wearables from Huami/Zepp servers";
      homepage = "https://codeberg.org/argrento/huami-token";
      license = licenses.mit;
      mainProgram = "huami-token";
    };
  };
in
{
  # Amazfish: the actual companion app for my Amazfit GTR2e (steps,
  # notifications, watch face management, ...). A system-wide Flatpak
  # install is fine here, unlike Spotify in home.nix — nothing needs to
  # patch its files in place.
  services.flatpak.packages = [
    "uk.co.piggz.amazfish" # Amazfit GTR2e companion app
  ];

  environment.systemPackages = [
    huami-token # fetches the watch's Bluetooth pairing auth key from Huami/Zepp's servers
  ];

  # Pulls the Bluetooth pairing auth key for my Amazfit watch from
  # Huami/Zepp's servers via huami-token above, so I can paste it into
  # Amazfish's pairing screen. My password is still typed interactively by
  # huami-token itself — never stored anywhere. This requires the watch to
  # already be paired AND synced at least once in the Zepp app, otherwise
  # huami-token comes back with no devices. I declare this here (rather
  # than in home.nix, like the other .local/bin scripts) so this whole
  # module, including its user-facing helper, can be dropped in one shot if
  # I ever retire Amazfish.
  home-manager.users.${username}.home.file.".local/bin/amazfit-get-key.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -uo pipefail

      email="''${1:-}"
      if [ -z "$email" ]; then
        read -rp "Zepp account email: " email
      fi

      echo "Make sure the watch is paired AND has synced at least once in the" >&2
      echo "Zepp app first — otherwise the auth key isn't registered on" >&2
      echo "Huami's servers yet and this will fail with 'No devices found'." >&2
      echo >&2

      output="$(huami-token -m amazfit -e "$email" -b)"
      echo "$output"

      echo
      echo "=== Auth key(s) for Amazfish ==="
      if ! echo "$output" | grep -E "MAC:|Key:"; then
        echo "No key found — did you sync the watch in the Zepp app first?"
        exit 1
      fi
      echo
      echo "Paste the key above into Amazfish: Settings > Device > Auth Key"
    '';
  };
}
