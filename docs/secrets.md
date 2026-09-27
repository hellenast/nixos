# Secrets

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) (`modules/system/secrets.nix`). Currently there's one: the ProtonVPN WireGuard config ([protonvpn.md](protonvpn.md)).

## How it works

`secrets/secrets.yaml` is encrypted for one age public key, declared in `.sops.yaml`. It's safe to keep in a public repo — only the matching private key can decrypt it, and that key never touches the repo. At system activation, sops-nix decrypts each secret into a root-only file under `/run/secrets/` (a tmpfs, gone on reboot), so nothing secret ever lands in the world-readable Nix store.

Because decryption happens during activation, the private key must already be on disk at `/var/lib/sops-nix/key.txt` (root-only, `0400`) **before** the first rebuild that uses it. Nix can't put it there. On a fresh install, `fresh-install.sh` disables the secrets modules until the key is back ([installing.md](installing.md)).

## Installing the key on a machine

From a backup of the key:

```
sudo install -D -m 0400 -o root -g root <age-key-file> /var/lib/sops-nix/key.txt
```

Check it's the right one: `sudo age-keygen -y /var/lib/sops-nix/key.txt` should print the public key in `.sops.yaml`.

## New machine or lost key

1. Generate a new keypair (`age-keygen -o key.txt`) and install the private key as above.
2. Put the new public key in `.sops.yaml`.
3. Re-encrypt for it: `sops updatekeys secrets/secrets.yaml`. This needs the *old* key to read the file; if that's gone, recreate the secrets from scratch (for ProtonVPN, download a new WireGuard config — [protonvpn.md](protonvpn.md)).

## Editing a secret

```
SOPS_AGE_KEY_FILE=/path/to/key.txt sops secrets/secrets.yaml
```

(or without the variable if the key is at sops' default lookup path). It opens the decrypted file in `$EDITOR` and re-encrypts on save. Deploy as usual afterwards — the deploy command copies `secrets/` too ([deploying.md](deploying.md)).
