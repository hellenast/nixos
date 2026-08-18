# ProtonVPN WireGuard setup

One-time steps to get `protonvpn.nix`'s tunnel actually running. See `protonvpn.nix` and the README's "ProtonVPN" section for how the module itself works.

## 1. Get a WireGuard config from ProtonVPN

1. Log into [account.proton.me](https://account.proton.me) (or the ProtonVPN dashboard) in a browser.
2. Go to **Downloads -> WireGuard configuration**.
3. Set the platform to "Router" or "GNU/Linux" (any generic option works — you're not using their native app).
4. Choose the country/server you want to route through. Note some locations require a paid plan, not the free tier.
5. Give the config a name if asked, then click **Create**. It downloads a `.conf` file, e.g. `protonvpn-XX-XX-123.conf`.

## 2. Put the config where the module expects it

```
sudo mkdir -p /etc/protonvpn
sudo mv ~/Downloads/protonvpn-*.conf /etc/protonvpn/proton.conf
sudo chmod 600 /etc/protonvpn/proton.conf
```

Kept outside the Nix store deliberately — store paths are world-readable, and this file has your WireGuard private key in it. The module expects it at exactly this path (`/etc/protonvpn/proton.conf`).

## 3. Deploy (only needed if `protonvpn.nix` itself hasn't been deployed yet)

```
sudo cp ~/nixos/*.nix /etc/nixos/ && sudo nixos-rebuild switch --flake .#
```

If the module is already deployed and you're just placing the config for the first time (or replacing it), skip straight to step 4 — no rebuild needed.

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

Repeat step 1 with a different server, overwrite `/etc/protonvpn/proton.conf` with the new file, then repeat step 4 (`sudo systemctl restart protonvpn-wg`) — no redeploy needed. Same command if Proton ever rotates keys on you.

## Troubleshooting

- `.wg-quick-wrapped: '/etc/protonvpn/proton.conf' does not exist` in `systemctl status protonvpn-wg` — step 2 hasn't been done yet (or the file got moved/deleted).
- `protonvpn-netns` failed — check `sudo journalctl -u protonvpn-netns` for the actual `ip` error; usually means the namespace/veth already exist from a previous run (reboot clears this, or `sudo ip netns del protonvpn && sudo ip link del pvpn-host` first).
- Tunnel is up but `curl ifconfig.me` inside the namespace times out — check `sudo iptables -t nat -L POSTROUTING -n` for the `MASQUERADE` rule on `10.10.10.0/24`, and confirm `net.ipv4.ip_forward` is `1` (`sysctl net.ipv4.ip_forward`).
- A VPN-only GUI app (e.g. "Vesktop (VPN)") launches but looks wrong — huge cursor, missing tray icon, wrong theme — that's `protonvpn-run` failing to carry your session's env vars (`XCURSOR_THEME`, `DBUS_SESSION_BUS_ADDRESS`, etc.) through both `sudo` hops into the namespace. Check `protonvpnRun`'s `passthroughEnvVars` list in `protonvpn.nix` includes whatever var is missing, and that the sudo rule for `ip netns exec protonvpn *` has both `NOPASSWD` and `SETENV` in its `options` — without `SETENV`, sudo silently drops the `VAR=value` assignments before they ever reach the namespace.
