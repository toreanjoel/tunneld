# Tunneld — Ad Copy

Marketing copy for tunneld, written to match the **actual shipped architecture**
(runtime-agnostic, wired-only, Caddy + WireGuard). Use this to replace the
outdated tunneld.io copy that still advertises mesh / zrok / SQM / wireless-first.

---

## Tagline / hero

> **A subnet in your pocket.**

> One ARM64 box. Your own private network. Every machine you own — local or
> remote — reachable as if it were plugged into the same switch.

---

## Short ad (social / one-liner)

**Tunneld** turns a $50 ARM64 SBC into a wired edge gateway for your private
subnet. It discovers what's *listening* on any Linux box (`ss -tlnp`), reaches
remote VPSes over a WireGuard overlay as if they were local, and exposes
services on the LAN or the public internet with Caddy. No containers to
manage. No agent daemons on your machines. Just two things installed anywhere:
**WireGuard and Caddy.**

---

## Landing page copy

### The network, in a box

Tunneld is software for a dual-NIC ARM64 single-board computer that turns it
into a **wired edge gateway** for a private subnet. Plug devices into the
downstream port and they get DHCP, DNS, and a name (`*.tunneld.lan`) — nothing
on the subnet needs configuring. It just works.

### A resource is an address, not a container

Tunneld never asks *"what runtime is this?"* It asks *"what is listening?"* A
single command — `ss -tlnp` — enumerates every listening socket on any Linux
host, whether the thing behind it is Docker, Incus, systemd, a Go binary in
tmux, or a runtime that doesn't exist yet. Pick one from the list; it becomes a
resource. Containers stay visible; they're just no longer something you have
to manage.

### WireGuard makes remote machines local

Your SBC moves and often sits behind NAT; your VPSes have stable public IPs.
So tunneld's gateway **dials out** to each machine over WireGuard, bringing
every enrolled host onto one overlay. A service on a VPS in another datacenter
is reachable at `myapp.tunneld.lan:18000` — no SSH tunnels, no port-forward
dance, no orphaned processes after a reboot.

### Expose on the LAN or the public internet

Caddy is a single static binary with a JSON admin API — no templates, no
reload dance. Tunneld drives it to expose a resource on the LAN
(`<name>.tunneld.lan:18000`) or publicly on a machine's own Caddy
(`http://<vm-ip>:8080`). Point DNS at a hostname and the same object provisions
TLS automatically. One object, one field, no migration.

### Per-device egress, one click

Route any device on your subnet through any exit-capable machine. Adding a
device to an exit is one `ip rule`; removing it is one delete. Pick "Local" or
any exit node from a dropdown — and choose whether DNS follows the exit or
stays local. No silent surprises.

### A control plane for agents, not agents on your machines

Tunneld is the chokepoint: egress policy, audit log, and scoped bearer tokens
all live in one place. A single scoped token lets one agent actuate the whole
fleet over the SSH transport that already exists — no agent daemon on every
host, no multiplied credential surface.

### Wired only. Deliberately.

No Wi-Fi bridging. No mesh. No zrok. No SQM. Tunneld installs exactly two
things on a target — **WireGuard and Caddy** — and nothing else. If a task
needs a third package, the operator SSHes in and does it; tunneld surfaces the
details and discovers the result. That's the whole product, and it's why it
stays small, predictable, and yours.

---

## Feature bullets

- **Runtime-agnostic discovery** — `ss -tlnp` finds what's listening on any
  Linux host; containers are visible but never required.
- **WireGuard overlay** — remote machines become local; the gateway dials out,
  so NAT is a non-issue.
- **Caddy exposure** — LAN names and public ports from one JSON object; TLS
  auto-provisions when you add a hostname.
- **Per-device egress** — route any device through any exit node with one
  click; DNS choice is explicit.
- **Agent API** — scoped, revocable bearer tokens, full audit log, async jobs.
- **Self-contained** — no database, just atomic JSON files; runs on a small
  ARM64 SBC.
- **Idempotent by design** — every operation is `ensure_*`; reboots are
  uneventful.

---

## What it is NOT (honest copy)

- Not a container manager. Containers are just things that listen on ports.
- Not a mesh / relay coordinator. One gateway, one overlay.
- Not wireless. Wired only, on purpose.
- Not an agent platform. One control plane, one key, one audit trail.
- Not a cloud. Machines you own or rent, enrolled by you.

---

## CTA

> **A subnet in your pocket.** Build it on a $50 SBC.
> [Get started →](https://github.com/toreanjoel/tunneld)
