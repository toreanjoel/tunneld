# Tunneld Build & Deploy Runbook

End-to-end steps for building the release on a Mac, deploying it to a tunneld gateway, enrolling
a remote machine over the WireGuard overlay, and exposing its services on the LAN.

> **Who this is for:** a human or an agent that needs to (1) build, (2) deploy, (3) connect
> machines, (4) route per-device egress. Each section is self-contained.
>
> Off-LAN / internet exposure is **not** part of tunneld. Resources are reachable on the LAN
> (`<name>.tunneld.lan:18000`) and over the overlay; anything public is operator-managed and
> lives outside this runbook.

---

## 1. Build the release on a Mac

### 1.1 Prerequisite: Docker

The build runs inside the official `elixir:1.17-slim` Docker image.

```bash
command -v docker && docker version --client >/dev/null 2>&1   && echo "Docker OK" || echo "Docker MISSING"
```

### 1.2 Run the builder

From the repo root:

```bash
cd <repo-root>          # e.g. ~/work/tunneld
./build_release.sh
```

**macOS adaptations:** use a patched copy (no `sudo`, `shasum -a 256` instead of `sha256sum`),
and back up + restore `mix.lock`:

```bash
sed -e 's/sudo docker/docker/g' -e 's/sudo chown/chown/g'     -e 's/sha256sum/shasum -a 256/g' build_release.sh > /tmp/build_release_mac.sh
chmod +x /tmp/build_release_mac.sh
cp mix.lock /tmp/mix.lock.bak
/tmp/build_release_mac.sh
cp /tmp/mix.lock.bak mix.lock
```

### 1.3 Output

The build writes to `~/tunneld_build/`: `tunneld-pre-alpha.tar.gz`, `checksums.txt`,
`metadata.json`. Verify:

```bash
cd ~/tunneld_build && shasum -a 256 tunneld-pre-alpha.tar.gz && cat checksums.txt
```

### 1.4 Stage into the installer repo (optional)

```bash
cd <tunneld-installer-repo-root>
cp ~/tunneld_build/tunneld-pre-alpha.tar.gz releases/
cp ~/tunneld_build/checksums.txt releases/
cp ~/tunneld_build/metadata.json releases/
git add releases/ && git commit -m "release: v$(cat releases/metadata.json | grep version | cut -d'"' -f4)" && git push
```

---

## 2. Deploy to a device (given an IP)

The device runs the tunneld gateway. The release tarball extracts into `/opt/tunneld`.

### 2.1 Copy the tarball to the device

```bash
scp ~/tunneld_build/tunneld-pre-alpha.tar.gz <user>@<DEVICE_IP>:/tmp/
```

### 2.2 Extract and restart on the device

```bash
ssh <user>@<DEVICE_IP>
sudo tar -xzf /tmp/tunneld-pre-alpha.tar.gz -C /opt/tunneld
sudo systemctl restart tunneld
sudo systemctl status tunneld
```

### 2.3 Verify

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://<DEVICE_IP>/
# expect HTTP 200
sudo journalctl -u tunneld -n 50   # if it fails
```

> **Rollback:** keep the previous tarball and re-extract it the same way if the new build
> misbehaves.

---

## 3. Enroll a machine & bring it onto the WireGuard overlay

Tunneld discovers what is *listening* on a machine (`ss -tlnp`) and makes remote machines local
via a WireGuard overlay. The gateway dials out to each machine.

### 3.1 Prerequisites on the target machine

- A Linux host reachable over SSH (Debian/Ubuntu recommended).
- **Inbound UDP `51821` must be allowed** in the target's firewall. For a cloud VPS this is a
  provider security-group rule (e.g. Vultr "inbound UDP 51821"). This is **not** the OS
  firewall — tunneld already opens that itself (`ufw allow 51821/udp`, see
  `Overlay.install_target/3`) — you must open it in the **provider console**.

  > The port is **51821**, not 51820. `51820` is the legacy standalone `wgtest` tunnel.
  > Per-machine overlays use `51821` (`@wg_port` in `lib/tunneld/overlay.ex`). Opening 51820
  > looks correct and changes nothing.

  Exactly two inbound ports are needed on a managed machine: **TCP 22** (tunneld's control
  plane — `SSH.run/3` dials the machine's *public* address, not the overlay) and **UDP 51821**
  (the overlay). Tunneld opens nothing else on a target — it does not install or drive Caddy
  there; Caddy is gateway-side only.

  The gateway itself needs **no** inbound rules. It dials out and holds the NAT mapping open
  with `PersistentKeepalive = 25`, which is what lets it sit behind NAT and move.
- The operator installs tunneld's public key into the target's `~/.ssh/authorized_keys`.

### 3.2 Enroll

1. Dashboard → **Machines → Enroll machine**: name, address, SSH port, user.
2. Tunneld shows the **public key** — install it on the target's `authorized_keys`.
3. Probe → the machine shows OS/arch/CPU/RAM/runtimes.

### 3.3 Bring up the overlay

`Tunneld.Overlay.ensure_peer/1` installs `wireguard-tools` on the target, exchanges keys,
writes `/etc/wireguard/wg-<hash>.conf` on both sides, and brings up `wg-quick@wg-<hash>`
(`<hash>` is the first 8 hex chars of `sha256(machine_id)` — wg-quick caps interface names at
15 chars). The
machine gets an overlay IP (e.g. `10.88.0.2`) and its services become reachable as if local.

**Verify on the target, not tunneld's word:**

```bash
wg show            # handshake present
ip -o addr show wg-*  # overlay iface up
```

Read `wg show` on the **gateway** as follows — it separates "blocked" from "misconfigured":

| Symptom | Meaning |
|---|---|
| `transfer: 0 B received`, non-zero sent, no `latest handshake` line | Handshakes are leaving and nothing is coming back. The port is blocked **upstream of the VM** — almost always the provider firewall. Confirm with `tcpdump -ni any udp port 51821` on the target: zero captured packets proves they never arrive. |
| `latest handshake` present, traffic both ways | Overlay is healthy. |

The gateway retries every 25s, so after opening the provider rule the tunnel comes up on its
own within about half a minute — **no re-enrollment needed**. Re-enrolling instead of waiting
mints a *new* machine id, hence a new `wg-<hash>` interface, and leaves the previous one
behind `systemctl enable`d on both hosts.

The dashboard polls overlay state every 15s, so the status dot and the panel's `WireGuard`
field catch up on their own once the handshake lands.

### 3.4 Expose a service over the overlay

1. Dashboard → machine → **Listeners** shows `ss -tlnp` output. Click **make resource** on a row.
2. The resource's backend is routed via `Overlay.address_for/1` (overlay IP for remote machines).
3. Reach it at `http://<name>.tunneld.lan:18000` — no SSH tunnel, and it survives a gateway reboot.

---

## 4. Per-device egress (M6)

Route a subnet device's traffic out through an exit machine.

- **On the exit machine:** enable `net.ipv4.ip_forward=1` (persistent), add a `MASQUERADE`
  rule on its egress interface, allow forwarding on the WireGuard interface, and set the
  gateway peer's `AllowedIPs` to include the LAN subnet.
- **On the gateway:** give the exit machine a routing table
  (`ip route add default dev wg-<hash> table <N>`), and route a device with one rule
  (`ip rule add from <device_ip> lookup <N>`). Removing a device is one delete.

> **Important:** only ever route *device* traffic — never the gateway's own source IP, or you
> will lock yourself out of the gateway. Always keep a rollback path.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `docker: command not found` | Install Docker (see 1.1) |
| `Permission denied` on deploy | Wrong SSH user/key; use the device's real user |
| `systemctl restart tunneld` fails | `sudo journalctl -u tunneld -n 50` |
| WireGuard handshake won't establish | Open inbound UDP/**51821** in the **provider** firewall (not the OS). `0 B received` with non-zero `sent` in `wg show` is this, every time |
| Machine reads `ready` but Terminal times out | Only the terminal uses the overlay IP; probe/listeners/exit use the public IP. So `ready` says nothing about the tunnel — check the `WireGuard` field |
| Remote service not reachable | Confirm the machine is a WG peer (`wg show`) and the resource pool uses the overlay IP |
| Egress routes but times out | Confirm ip_forward + MASQUERADE on the exit and FORWARD allow on its WG iface |
