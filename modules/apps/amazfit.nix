{ pkgs, lib, username, ... }:

# Companion app and pairing-key tooling for an Amazfit GTR2e watch.
# Pairing is interactive every time — see docs/manual-setup.md.

let
  # huami-token: fetches the watch's Bluetooth auth key from Huami/Zepp's
  # servers (Zepp account login). Amazfish needs that key to pair. Not in
  # nixpkgs, so it's packaged here.
  huami-token = pkgs.python3.pkgs.buildPythonApplication rec {
    pname = "huami-token";
    version = "0.8.0";
    pyproject = true;

    # A full commit hash in `rev` is enough for fetchGit to be pure (and
    # reproducible) under flakes; no separate hash needed.
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

    # The test suite needs real Zepp account credentials.
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
  # Amazfish: the companion app itself (steps, notifications, watch faces,
  # ...). Installed through desktop/flatpak.nix.
  services.flatpak.packages = [
    "uk.co.piggz.amazfish" # Amazfit GTR2e companion app
  ];

  environment.systemPackages = [
    huami-token # fetches the watch's Bluetooth pairing auth key from Huami/Zepp's servers
  ];

  # Wraps huami-token to print just the key to paste into Amazfish. The
  # password is typed into huami-token interactively and never stored. The
  # watch must already be paired and synced once in the Zepp app, or
  # huami-token finds no devices. Declared here rather than in home/ so this
  # one file holds the whole Amazfit setup.
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
