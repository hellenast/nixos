# ProtonVPN

`modules/network/protonvpn.nix` gives per-app split tunnelling: a dedicated network namespace with its own WireGuard tunnel. Only apps started through a "<Name> (VPN)" launcher (or `protonvpn-run <cmd>`) use the VPN; everything else keeps the normal route.

- Which apps get a VPN launcher is the `apps` list near the top of `protonvpn.nix` (Vesktop is there already). Edit it and redeploy; each entry gets a "<Name> (VPN)" launcher next to its normal one.
- The tunnel comes up by itself at every boot (`protonvpn-netns` and `protonvpn-wg` are both wanted by `multi-user.target`).
- The WireGuard config (private key included) lives encrypted in `secrets/secrets.yaml` and is decrypted at activation into `/run/secrets/protonvpn.conf` (root-only, gone on reboot) by `modules/system/secrets.nix`. That needs the age private key installed first — see [secrets.md](secrets.md).

The rest of this page is the one-time setup, and how to swap in a new config later.

## 1. Get a WireGuard config from ProtonVPN

1. Log into [account.proton.me](https://account.proton.me) (or the ProtonVPN dashboard) in a browser.
2. Go to **Downloads -> WireGuard configuration**.
3. Set the platform to "Router" or "GNU/Linux" (any generic option works — I'm not using their native app).
4. Choose the country/server you want to route through. Note some locations require a paid plan, not the free tier.
5. Give the config a name if asked, then click **Create**. It downloads a `.conf` file, e.g. `protonvpn-XX-XX-123.conf`.

## 2. Encrypt it into secrets.yaml

```
cd ~/nixos
SOPS_AGE_KEY_FILE=/path/to/your/age/private/key sops secrets/secrets.yaml
```

This opens the decrypted contents in `$EDITOR`. Replace the `protonvpn-conf` value with the downloaded file's contents (keep the `|` block-literal form, indented the same as before), save, and quit — `sops` re-encrypts it on write. Delete the downloaded `.conf` file afterwards; it has my private key in plaintext and doesn't need to exist outside `secrets.yaml` once it's in there.

## 3. Deploy

The normal deploy ([deploying.md](deploying.md)) — it copies `secrets/` along with the modules:

```
sudo rm -rf /etc/nixos/modules /etc/nixos/hosts && sudo cp -r ~/nixos/*.nix ~/nixos/modules ~/nixos/hosts ~/nixos/secrets /etc/nixos/ && cd /etc/nixos && sudo nixos-rebuild switch --flake .#
```

Swapping in a new config when everything is already deployed still needs this rebuild: sops-nix only decrypts during activation, so copying `secrets.yaml` alone doesn't update `/run/secrets/protonvpn.conf`. Then restart the tunnel (step 4).

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

The last command should print the ProtonVPN server's IP, not my real one.

## 6. Launch VPN-only apps

Use the "<Name> (VPN)" entries in the app launcher (e.g. "Vesktop (VPN)") instead of the plain ones — those run through `protonvpn-run`. Which apps get one is controlled by the `apps` list near the top of `modules/network/protonvpn.nix`.

## Changing server/country later

Repeat step 1 with a different server, then steps 2-4 to re-encrypt and redeploy. Same process if Proton ever rotates keys on me.

## Troubleshooting

- `protonvpn-wg.service` fails immediately, or `/run/secrets/protonvpn.conf` doesn't exist — the secret didn't decrypt. Check `sudo journalctl -u sops-nix` (or look for `setupSecrets` output during activation) and confirm `/var/lib/sops-nix/key.txt` actually exists and is the right key (`age-keygen -y /var/lib/sops-nix/key.txt` should print the public key listed in `.sops.yaml`).
- `protonvpn-netns` failed — check `sudo journalctl -u protonvpn-netns` for the actual `ip` error; usually means the namespace/veth already exist from a previous run (reboot clears this, or `sudo ip netns del protonvpn && sudo ip link del pvpn-host` first).
- Tunnel is up but `curl ifconfig.me` inside the namespace times out — check `sudo iptables -t nat -L POSTROUTING -n` for the `MASQUERADE` rule on `10.10.10.0/24`, and confirm `net.ipv4.ip_forward` is `1` (`sysctl net.ipv4.ip_forward`).
- A VPN-only GUI app (e.g. "Vesktop (VPN)") launches but looks wrong — huge cursor, missing tray icon, wrong theme — that's `protonvpn-run` failing to carry my session's env vars (`XCURSOR_THEME`, `DBUS_SESSION_BUS_ADDRESS`, etc.) through both `sudo` hops into the namespace. Check `passthroughEnvVars` in `modules/network/protonvpn.nix` includes whatever var is missing, and that the sudo rule for `ip netns exec protonvpn *` has both `NOPASSWD` and `SETENV` in its `options` — without `SETENV`, sudo silently drops the `VAR=value` assignments before they ever reach the namespace.
