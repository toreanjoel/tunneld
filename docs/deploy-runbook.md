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

## 4. Publish a resource on a machine's public IP

Serve a subnet service on the internet through a managed machine. Plain `IP:port` only —
no domain, no TLS. For those, open a Terminal on the machine and configure it yourself.

**How it routes:**

```
internet -> <machine_public_ip>:<port> -> WireGuard -> gateway 10.88.0.1:18000 -> the pool
```

The machine's Caddy proxies to the **gateway's** Caddy, rewriting `Host` to
`<name>.tunneld.lan` so the gateway's existing route matches. Traffic terminates on the
gateway (`INPUT`, where tcp/18000 is already open on every interface) and the gateway then
opens its own connection to the backend (`OUTPUT`). It never crosses the gateway's `FORWARD`
chain, so **publishing needs no new gateway firewall rules and exposes no LAN device to the
machine**.

**Steps:**

1. Create the resource as usual (its pool points at a LAN device, e.g. `10.0.0.44:8000`).
2. Dashboard → resource → **Publish**: pick a machine and a TCP port.
3. Tunneld installs Caddy on the machine, writes `/etc/tunneld-caddy.json`, enables the
   `tunneld-caddy` unit, and runs `ufw allow <port>/tcp`.
4. **Open inbound TCP `<port>` in the machine's cloud-provider firewall.** Tunneld cannot do
   this — same class of step as UDP/51821 for WireGuard. The modal shows the exact rule.
5. Confirm it yourself from somewhere off this subnet — the modal gives you the exact
   command: `curl -v http://<machine_ip>:<port>`. Tunneld shows no "healthy" badge for a
   published resource on purpose: it cannot see your provider's firewall, so a green dot
   would only ever mean "we wrote some config".

> Published means public: plain HTTP, no authentication unless the service provides its own.

**Pick a machine near the gateway.** Every request makes the full round trip, so a machine on
another continent adds that latency to every page load.

---

## 5. Client access (phones, laptops, other people)

A **client** is a person's device that should reach this subnet from anywhere. It gets its own
keypair and an address in `10.88.1.0/24`, and it **always terminates on the gateway**:

```
at home   client -> 10.0.0.1:51822                       (one hop, no VPS involved)
away      client -> <machine>:51822 -DNAT-> 10.88.0.1:51822   (the machine is a door)
```

A machine forwards that port into the tunnel it already holds with the gateway. It never sees
a client key and never runs a second WireGuard instance, so you can add or swap machines
without reissuing anything. Same keypair, same address, same peer — only `Endpoint` differs.

**Enrolling a client**

1. Dashboard → **Clients** → name the device, choose an endpoint:
   - *this gateway* — home network only, no VPS in the path
   - *via `<machine>`* — reachable from anywhere
2. Scan the QR with the WireGuard app, or copy the config.
3. **The private key is shown once and never stored.** Lost it? Revoke and enrol again.

**Roaming.** WireGuard allows one `Endpoint` per peer, so for a device that is sometimes home
and sometimes away, either use the app's on-demand activation with your home SSID excluded
(the tunnel is not needed at home — you are already on the LAN), or keep two profiles that
differ only in `Endpoint`.

**Access.** A new client reaches the overlay and nothing else. LAN access is granted per host
and enforced by FORWARD rules on the gateway — never by the client's own `AllowedIPs`, which
the client owns and can change at will.

**Provider firewall.** Machines need inbound **UDP 51822** as well as 51821. Both are listed
in the enrolment modal so it is one trip to the console.

**MTU.** Client configs ship `MTU = 1360`. The away path is doubly encapsulated (the client's
tunnel inside the gateway's tunnel to the machine); at 1420 TCP still works while UDP quietly
blackholes.

---

## 6. Per-device egress (M6)

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
| Client connects at home but not away | Inbound **UDP 51822** is not open in that machine's provider firewall. `wg show wg-clients` on the gateway will show no handshake for that peer |
| Client connects, LAN hosts unreachable | Expected until you grant access — a new client reaches the overlay only. Grant per host in the Clients panel |
| Client works for SSH but the video stalls | MTU. The away path is doubly encapsulated; keep the client at 1360 |
| Published URL times out | Inbound TCP on that port is not open in the **provider** firewall. Tunneld opens the machine's own firewall, never the provider's |
| Published URL returns 502 | The gateway's Caddy has no route for that resource, or the pool backend is down. Check the resource's LAN URL works first |
| Remote service not reachable | Confirm the machine is a WG peer (`wg show`) and the resource pool uses the overlay IP |
| Egress routes but times out | Confirm ip_forward + MASQUERADE on the exit and FORWARD allow on its WG iface |
