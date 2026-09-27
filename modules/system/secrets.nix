{ inputs, ... }:

# sops-nix: decrypts secrets/secrets.yaml (age-encrypted, safe to commit)
# during activation into /run/secrets/* — a root-only tmpfs, gone on
# reboot. Nothing secret ever lands in the world-readable Nix store.
#
# Decryption needs the age private key on disk *before* the first rebuild
# that uses it; Nix can't create it. See docs/secrets.md for installing the
# key, editing secrets, and rotating to a new key. The matching public key
# is in .sops.yaml.
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.defaultSopsFile = ../../secrets/secrets.yaml;

  # ProtonVPN's WireGuard config, read by network/protonvpn.nix.
  sops.secrets."protonvpn-conf" = {
    owner = "root";
    mode = "0400";
    # wg-quick requires a config path ending in ".conf", and names the
    # interface after the file's basename — the default
    # /run/secrets/protonvpn-conf would fail both.
    path = "/run/secrets/protonvpn.conf";
  };
}
