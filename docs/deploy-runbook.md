# Tunneld Build & Deploy Runbook

End-to-end steps for building the release on a Mac, deploying it to a tunneld gateway, enrolling
a remote machine over the WireGuard overlay, and exposing a service publicly.

> **Who this is for:** a human or an agent that needs to (1) build, (2) deploy, (3) connect
> machines, (4) expose services. Each section is self-contained.

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
cd /Users/toreanjoel/work/personal/tunneld
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
cd /Users/toreanjoel/work/personal/tunneld-installer
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
- **Inbound UDP on the WireGuard port (default `51820`) must be allowed** in the target's
  firewall. For a cloud VPS this is a provider security-group rule (e.g. Vultr "inbound UDP
  51820"). This is **not** the OS firewall — open it in the provider console.
- The operator installs tunneld's public key into the target's `~/.ssh/authorized_keys`.

### 3.2 Enroll

1. Dashboard → **Machines → Enroll machine**: name, address, SSH port, user.
2. Tunneld shows the **public key** — install it on the target's `authorized_keys`.
3. Probe → the machine shows OS/arch/CPU/RAM/runtimes.

### 3.3 Bring up the overlay

`Tunneld.Overlay.ensure_peer/1` installs `wireguard-tools` on the target, exchanges keys,
writes `/etc/wireguard/wg-<id>.conf` on both sides, and brings up `wg-quick@wg-<id>`. The
machine gets an overlay IP (e.g. `10.88.0.2`) and its services become reachable as if local.

**Verify on the target, not tunneld's word:**

```bash
wg show            # handshake present
ip -o addr show wg-*  # overlay iface up
```

### 3.4 Expose a service over the overlay

1. Dashboard → machine → **Listeners** shows `ss -tlnp` output. Click **make resource** on a row.
2. The resource's backend is routed via `Overlay.address_for/1` (overlay IP for remote machines).
3. Reach it at `http://<name>.tunneld.lan:18000` — no SSH tunnel, and it survives a gateway reboot.

---

## 4. Public exposure (M4)

Drive the **machine's own Caddy** admin API over the overlay to expose a service publicly.

1. Install Caddy on the machine; bind its admin API to the **overlay address only**
   (`admin 10.88.0.2:2019`), never `0.0.0.0` / public.
2. Tunneld pushes a public config with the resource's `listen` field:
   - `"8080"` → `:8080`, no domain/TLS (day one).
   - `"app.example.com"` → `:80/:443` with auto-TLS (point DNS to the machine, change one field).
3. **Open the exposed TCP port in the machine's provider firewall** (e.g. Vultr inbound TCP
   `8080`) for public internet reachability.

---

## 5. Per-device egress (M6)

Route a subnet device's traffic out through an exit machine.

- **On the exit machine:** enable `net.ipv4.ip_forward=1` (persistent), add a `MASQUERADE`
  rule on its egress interface, allow forwarding on the WireGuard interface, and set the
  gateway peer's `AllowedIPs` to include the LAN subnet.
- **On the gateway:** give the exit machine a routing table
  (`ip route add default dev wg-<id> table <N>`), and route a device with one rule
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
| WireGuard handshake won't establish | Open inbound UDP/51820 in the **provider** firewall (not the OS) |
| Remote service not reachable | Confirm the machine is a WG peer (`wg show`) and the resource pool uses the overlay IP |
| Public port times out | Open the exposed TCP port in the provider firewall |
| Egress routes but times out | Confirm ip_forward + MASQUERADE on the exit and FORWARD allow on its WG iface |
