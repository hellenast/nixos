# ProtonVPN WireGuard setup

One-time steps to get `protonvpn.nix`'s tunnel actually running. See `protonvpn.nix`, `secrets.nix`, and the README's "ProtonVPN" and "Secrets" sections for how the pieces fit together.

The WireGuard config (private key included) is stored encrypted in `secrets/secrets.yaml` via [sops-nix](https://github.com/Mic92/sops-nix) — safe to commit, even to a public repo — and decrypted at boot into `/run/secrets/protonvpn.conf` (root-only, wiped on reboot). Decryption needs the age private key already installed at `/var/lib/sops-nix/key.txt` — see the README's "Secrets" section if that hasn't been done yet on this machine.

## 1. Get a WireGuard config from ProtonVPN

1. Log into [account.proton.me](https://account.proton.me) (or the ProtonVPN dashboard) in a browser.
2. Go to **Downloads -> WireGuard configuration**.
3. Set the platform to "Router" or "GNU/Linux" (any generic option works — you're not using their native app).
4. Choose the country/server you want to route through. Note some locations require a paid plan, not the free tier.
5. Give the config a name if asked, then click **Create**. It downloads a `.conf` file, e.g. `protonvpn-XX-XX-123.conf`.

## 2. Encrypt it into secrets.yaml

```
cd ~/nixos
SOPS_AGE_KEY_FILE=/path/to/your/age/private/key sops secrets/secrets.yaml
```

This opens the decrypted contents in `$EDITOR`. Replace the `protonvpn-conf` value with the downloaded file's contents (keep the `|` block-literal form, indented the same as before), save, and quit — `sops` re-encrypts it on write. Delete the downloaded `.conf` file afterwards; it has your private key in plaintext and doesn't need to exist outside `secrets.yaml` once it's in there.

## 3. Deploy

```
sudo mkdir -p /etc/nixos/secrets && sudo cp ~/nixos/secrets/secrets.yaml /etc/nixos/secrets/secrets.yaml
sudo cp ~/nixos/*.nix /etc/nixos/ && sudo nixos-rebuild switch --flake .#
```

The first line is easy to forget — the second command's `*.nix` glob doesn't pick up `secrets/secrets.yaml` since it isn't a `.nix` file.

If `protonvpn.nix`/`secrets.nix` are already deployed and you're just swapping in a new config, skip straight to step 4 — no rebuild needed, just re-copy `secrets.yaml` and restart the service.

## 4. Start (or restart) the tunnel

```
sudo systemctl restart protonvpn-wg
sudo systemctl status protonvpn-netns protonvpn-wg
```

## 5. Verify it's actually working

```
sudo ip netns exec protonvpn wg show
sudo ip netns exec protonvpn curl -s ifconfig.me
```

The last command should print the ProtonVPN server's IP, not your real one.

## 6. Launch VPN-only apps

Use the "<Name> (VPN)" entries in your app launcher/rofi (e.g. "Vesktop (VPN)") instead of the plain ones — those are the ones wired through `protonvpn-run`. Which apps get one is controlled by the `apps` list near the top of `protonvpn.nix`.

## Changing server/country later

Repeat step 1 with a different server, then steps 2-4 to re-encrypt and redeploy. Same process if Proton ever rotates keys on you.

## Troubleshooting

- `protonvpn-wg.service` fails immediately, or `/run/secrets/protonvpn.conf` doesn't exist — the secret didn't decrypt. Check `sudo journalctl -u sops-nix` (or look for `setupSecrets` output during activation) and confirm `/var/lib/sops-nix/key.txt` actually exists and is the right key (`age-keygen -y /var/lib/sops-nix/key.txt` should print the public key listed in `.sops.yaml`).
- `protonvpn-netns` failed — check `sudo journalctl -u protonvpn-netns` for the actual `ip` error; usually means the namespace/veth already exist from a previous run (reboot clears this, or `sudo ip netns del protonvpn && sudo ip link del pvpn-host` first).
- Tunnel is up but `curl ifconfig.me` inside the namespace times out — check `sudo iptables -t nat -L POSTROUTING -n` for the `MASQUERADE` rule on `10.10.10.0/24`, and confirm `net.ipv4.ip_forward` is `1` (`sysctl net.ipv4.ip_forward`).
- A VPN-only GUI app (e.g. "Vesktop (VPN)") launches but looks wrong — huge cursor, missing tray icon, wrong theme — that's `protonvpn-run` failing to carry your session's env vars (`XCURSOR_THEME`, `DBUS_SESSION_BUS_ADDRESS`, etc.) through both `sudo` hops into the namespace. Check `protonvpnRun`'s `passthroughEnvVars` list in `protonvpn.nix` includes whatever var is missing, and that the sudo rule for `ip netns exec protonvpn *` has both `NOPASSWD` and `SETENV` in its `options` — without `SETENV`, sudo silently drops the `VAR=value` assignments before they ever reach the namespace.
