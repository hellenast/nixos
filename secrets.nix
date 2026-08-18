{ config, pkgs, ... }:

{
  # sops-nix: decrypts secrets/secrets.yaml (age-encrypted, safe to commit)
  # at activation time and drops the plaintext into /run/secrets/* (a
  # tmpfs, root-only, wiped on reboot) — nothing sensitive ever touches the
  # Nix store, which is world-readable by design.
  #
  # This needs an age private key present on disk *before* the first
  # `nixos-rebuild switch` that uses it, since decryption happens as part
  # of activation, not something Nix can generate on its own. One-time
  # manual setup, same pattern as the ProtonVPN conf file used to be:
  #   sudo install -D -m 0400 -o root -g root <age-key-file> /var/lib/sops-nix/key.txt
  # The matching public key (used in .sops.yaml's creation_rules, so `sops`
  # knows who to encrypt for) is:
  #   age1tzkgflevfv75ljn9t4uldd2hxm6vvxusn3ha9kgn6fleempdx5zquckxpf
  # Re-encrypt secrets/secrets.yaml for a new key with `sops updatekeys`.
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.defaultSopsFile = ./secrets/secrets.yaml;

  # ProtonVPN's WireGuard config (see protonvpn.nix, which reads it back
  # out via config.sops.secrets."protonvpn-conf".path). Used to live as a
  # plain file at /etc/protonvpn/proton.conf, owned by me and
  # world-readable — anyone with a shell on this machine could've read the
  # tunnel's private key. This is root-only (0400) and only exists at all
  # while the system is booted and activated.
  sops.secrets."protonvpn-conf" = {
    owner = "root";
    mode = "0400";
    # wg-quick requires its config argument to literally end in ".conf"
    # when given as a path (see protonvpn.nix's wgInterface, which is
    # derived from this file's basename) — sops-nix's default
    # /run/secrets/<name> path wouldn't satisfy that on its own.
    path = "/run/secrets/protonvpn.conf";
  };
}
