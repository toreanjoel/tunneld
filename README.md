# Tunneld

![Elixir](https://img.shields.io/badge/elixir-1.18+-purple)
![Phoenix](https://img.shields.io/badge/phoenix-1.7+-orange)
![Caddy](https://img.shields.io/badge/Caddy-2.x-green)![WireGuard](https://img.shields.io/badge/WireGuard-1.x-blue)
![Platform](https://img.shields.io/badge/platform-debian-red)

Software for a dual-NIC ARM64 single-board computer that turns it into a wired edge gateway for a private subnet. The core idea is **a resource is an address, not a container**: tunneld discovers what is *listening* on any Linux host (`ss -tlnp`) and exposes it — on the LAN and over a WireGuard overlay — via **Caddy** and **WireGuard**. It installs exactly one thing on a target: **WireGuard** (`wireguard-tools`). Caddy runs on the gateway only.

Each node is self-contained (no database — just atomic JSON files) and runs on a small ARM64 SBC. Plug devices into the downstream port, manage them from a real-time LiveView dashboard, and expose services on machines you've enrolled over SSH — locally, or remotely over WireGuard.

> **Prerequisites**
>
> - **Hardware**: An ARM64 SBC with two ethernet interfaces (Raspberry Pi, NanoPi, etc.)
> - **Operating System**: Debian-based OS
>
> Tunneld owns two NICs: one upstream (internet) and one downstream (your private subnet). It does not use Wi-Fi. Interface names are selected dynamically at install time and read from app config at runtime — never hardcoded.

---

## What it is

Tunneld is one box that does two jobs:

1. **It is the network.** It runs DHCP and DNS for your subnet, NATs your upstream connection, and gives every device and service a name (`*.tunneld.lan`). Nothing on the subnet needs configuring — it just works.
2. **It exposes what's listening.** Over SSH it reaches other machines (local boxes on the subnet, or remote VPSes), enumerates their listening sockets (`ss -tlnp`), and turns any of them into a named resource fronted by Caddy on the gateway — on the LAN, or over a WireGuard overlay.

Everything is reachable by name from anything on the subnet. No cloud, no accounts, no per-device setup. It works fully offline — local networking, DHCP, and name resolution keep functioning without internet.

```
WAN (upstream) ── Tunneld SBC ── LAN (downstream) ── switch ── devices
                      │
                      └── SSH ──> targets (local machines / remote VMs)
                                     └── WireGuard ──> remote machines are local
```

No Wi-Fi. No overlay network. No control-plane dependency.

---

## Real-world use cases

These are the scenarios the architecture actually enables today.

### Self-hosted AI lab, no cloud bill
Run an Ollama container on every spare box in your house (old laptops, NUCs, SBCs) — you start them, tunneld discovers the listener. Tunneld gives each one a `*.tunneld.lan` name and load-balances across them. Open `http://chat.tunneld.lan:18000` from your phone — no internet, no API key, no per-token charge.

### A personal cloud that survives an internet outage
Starlink drops, fiber gets cut, the ISP has a bad day — your LAN keeps humming. DHCP, DNS, file shares, media, and dashboards all stay up because the gateway *is* the network. Add a remote VPS as a managed machine and you've got a failover dev box reachable from the same dashboard.

### Homelab in a backpack
One ARM SBC + a few USB drives = a deployable edge node for a field site, a cabin, a boat, a pop-up event. Plug into any upstream (hotspot, Starlink, fiber) and it becomes the LAN: devices get addresses, services get names, and you promote listeners to resources from the LiveView UI on your phone. Pack up, move, replant.

### A fleet of game servers for your friends
Each game (Minecraft, Valheim, Factorio) runs in its own container on whatever box has spare RAM — you run it, tunneld discovers and exposes it. `minecraft.tunneld.lan`, `valheim.tunneld.lan` — your friends just type the name. Add a remote VPS as a managed machine and your crew plays even when your home IP changes.

### Remote dev environments you SSH into from the couch
Run a fresh container per project on any machine in the house (or a remote VPS); tunneld discovers what it is listening on and names it. Open a browser shell from the LiveView dashboard, or `ssh project.tunneld.lan`. Kill the container when you're done — state lives in git, not on your laptop. Your M-series MacBook stays cool; the heavy lifting happens on the noisy box in the closet.

### A "bring-your-own-device" workshop or classroom
Walk in with the tunneld SBC, plug it in. Every attendee's laptop gets a DHCP lease and can `curl` the device API — no accounts, no onboarding. They hit `http://notes.tunneld.lan`, `http://dataset.tunneld.lan`, `http://sandbox.tunneld.lan` and you've got a self-contained workshop environment with zero cloud dependency and zero per-seat setup.

### A 3D-printer / maker farm
Each printer host is a managed machine. You run an OctoPrint instance per printer; tunneld discovers it and exposes it as `printer-1.tunneld.lan`, load-balancing a shared dashboard. Add a remote VPS as a managed machine and you can monitor the farm from anywhere — the WireGuard overlay makes a remote printer look local.

### A privacy-first smart home with no vendor cloud
Home Assistant, Frigate (NVR), Node-RED, MQTT — all in containers on machines tunneld manages (you run them; tunneld discovers and exposes them). No data leaves the LAN. The gateway's DNS interception means even chatty devices stay inside. `home.tunneld.lan`, `cams.tunneld.lan`, `automations.tunneld.lan` — reachable from any device on the subnet, nowhere else.

### A red-team / CTF training range
Run vulnerable containers per exercise and tear them down per session; tunneld discovers each one and exposes it as `vuln-1.tunneld.lan`. The gateway isolates the range from the upstream. Tunneld does not create, start, stop or reset containers — it only discovers what is listening and points a name at it. Great for training a team without touching anything outside the subnet.

### An offline-first edge node for a remote site
A cabin, a boat, a research station, a construction trailer. Tunneld on the SBC + a 4G/Starlink upstream. Local devices get DNS and DHCP, local services keep working when the uplink dies, and a remote VPS acts as your managed "always-on" machine for things that *do* need internet — all seen from one dashboard.

The common thread: **the gateway owns the network, the fleet manager owns the compute, and everything is reachable by name from anything on the subnet — no cloud, no accounts, no per-device setup.**

---

## What it actually does (verified)

### Ethernet-first gateway
Connects upstream to the internet over one NIC and serves a private subnet over the other. Devices plug into the downstream port and receive IPs, DNS, and internet access — no existing router UI needed. Link state for both interfaces is read on demand from `/sys/class/net/<iface>/operstate` by `Tunneld.NetLink` (no GenServer, no polling). Everything is controlled through the Tunneld dashboard.

### DHCP + DNS via dnsmasq
dnsmasq runs on the LAN interface and provides:
- **DHCP** — every device on the subnet gets a lease (hostname, MAC, IP visible in the dashboard).
- **DNS forwarding** — queries on the subnet are intercepted via iptables and forwarded to a user-configured upstream resolver. Select any resolver from the dashboard — Cloudflare (`1.1.1.1`), Google (`8.8.8.8`), or a local Pi-hole on your network. Same-subnet DNS servers are supported via automatic prerouting rules.
- **Named resolution** — dnsmasq resolves any `*.tunneld.lan` name to the gateway, so named resources and exposed services are reachable by name across the subnet.

### NAT, forwarding, and DNS interception
iptables handles NAT masquerading, packet forwarding, and DNS redirection (port 53 → local dnsmasq on 5336) between the upstream and downstream interfaces. IP forwarding is enabled via sysctl at app start (prod only).

### Device management
- **Lease visibility** — every device on the subnet is listed with hostname, MAC, and IP, parsed from `/var/lib/misc/dnsmasq.leases` and broadcast to the dashboard via PubSub.
- **Online status** — ping probe, cached 30s.
- **Device tagging** — label devices with friendly names (e.g. `android-12345` → `kitchen-tablet`). Tags persist in `device_tags.json`.
- **Lease revocation** — kick a device off the network by removing its MAC from `dnsmasq.leases` and restarting dnsmasq. MAC-format validated to prevent command injection.

### Service monitoring
Watches the underlying systemd units: `dnsmasq`, `dhcpcd`, `caddy`. `check_service/1` runs `systemctl is-active` and auto-starts the unit if inactive. Logs are surfaced via `journalctl -u`.

### Auth
Sessions (in-memory, IP-keyed, TTL'd) + bcrypt admin credentials. Login and signup are in the LiveView dashboard. First-run onboarding is gated by an `onboarded` flag in `auth.json`.

> **Note:** WebAuthn is listed in the project structure as a future addition but is **not currently implemented**. Auth today is bcrypt + session.

### Works offline
Local networking, DHCP, and name resolution keep functioning without internet. The only internet-dependent features are geolocation and the OTA update checker, both of which are non-blocking and async.

### Runtime discovery (Machines + Runtime)
Enroll machines (local subnet devices or remote VPSes) that expose a Linux SSH endpoint. Tunneld generates an Ed25519 keypair per machine, displays the public half for you to install on the target, probes generic capabilities over SSH (OS, kernel, arch, CPU, RAM, detected runtimes), and enumerates listening sockets with `ss -tlnp`. Any listener can be promoted to a named resource.

- **Host specs surfaced per target** from a generic capability probe: `os`, `kernel`, `arch`, `cpu_count`, `memory_mb`, `detected_runtimes` (no container-runtime fields).
- **Listeners discovered live** with `ss -tlnp`; the target is the source of truth. Tunneld persists only the target list and credentials.
- **SSH transport** uses ControlMaster multiplexing (`ControlMaster=auto`, `ControlPersist=600`) so repeated commands reuse one persistent connection per machine.
- **Runtime-agnostic** — tunneld never asks "what runtime is this?", only "what is listening?". Incus/Docker/systemd/bare processes all work identically; it installs exactly one thing on a target: **WireGuard** (`wireguard-tools`).

### Local vs remote machines
The `location` field is inferred from the subnet (same `/24` as the gateway = `"local"`, otherwise
`"remote"`) but it now collapses into a single function, `Overlay.address_for/1`:

- **Local machine** → its LAN IP.
- **Remote machine** → its **overlay IP** (over the WireGuard tunnel). WireGuard makes remote
  machines local.

### Overlay (WireGuard)
Tunneld installs WireGuard (`wireguard-tools`) on each enrolled machine and brings up a `wg-<hash>` peer (`<hash>` is the first 8 hex chars of `sha256(machine_id)`; wg-quick caps interface names at 15 chars). The gateway
dials out to each machine (`PersistentKeepalive=25`, `Table=off` with hand-installed routes), so a
remote VPS's services become reachable as if they were on the subnet.

### Runtime discovery & resources
Tunneld discovers what is *listening* (`ss -tlnp`) on a machine; any listener can be promoted to a
**resource**. A resource is a named pointer to already-running backends:

- Caddy load-balances across healthy backends; each resource is reachable at
  `http://<name>.tunneld.lan:18000` (and on a per-resource loopback port bound to the gateway IP,
  `<gateway-ip>:2xxxx`, falling back to `127.0.0.1` — for manual/zrok/cloudflared-style exposure).
- Remote machines are reached over the overlay, so no SSH tunnel is involved and resources survive
  a gateway reboot.
- Pool entries are validated as `IP:port` before writing the Caddy upstream config (injection-safe).
- **No public-internet exposure at all.** Caddy runs on the gateway with two planes — the LAN
  server on `0.0.0.0:18000` and the per-resource loopback listener. Putting a resource on the
  internet is operator-managed and outside tunneld.

### Quick Expose
A subnet device can create, list, and remove a local resource with a single `curl` — no login. The gateway resolves the caller from its DHCP lease (`conn.remote_ip` matched against `dnsmasq.leases`) and validates a per-device allowlist (`expose_allowed.json`, MAC → boolean). The operator must explicitly allowlist a MAC before that device can Quick Expose.

```
POST   /api/v1/expose         create a local resource
GET    /api/v1/expose         list quick-exposed resources
DELETE /api/v1/expose/:name   remove a quick-exposed resource
```

### Device-facing read API
Any device with a DHCP lease from this gateway can query machine, resource, and health data without logging in (same device-resolution model as Quick Expose). Useful for CLI/scripts on subnet devices — these four routes are the whole device API:

```
GET /api/v1/device/machines                  list machines + status + capabilities
GET /api/v1/device/machines/:id              machine detail + health
GET /api/v1/device/resources                 list exposed resources
GET /api/v1/device/health                    gateway + service status
```

For example: `curl http://<gateway>/api/v1/device/machines`. The `/api/v1/machines*` (admin) endpoints remain password-protected for provisioning and lifecycle management.

### System resources
CPU, memory, disk, and **CPU temperature** (read from `/sys/class/thermal/thermal_zone0/temp`) are monitored and broadcast to the dashboard.

### Geolocation
The dashboard surfaces the gateway's public IP geolocation on an **offline SVG world map** (180 KB inlined in `geo_data/world_map.ex` — no CDN, works offline). Public IP is resolved from multiple endpoints (`ifconfig.me`, `icanhazip`, `ipify`) with exponential-backoff retry and `:stale`/`:unavailable` status.

### OTA update checker
Polls `raw.githubusercontent.com/toreanjoel/tunneld-installer/.../metadata.json` every 5 minutes, compares versions, and broadcasts to the dashboard when a new release is available.

### First-run setup wizard
Guided onboarding flow after initial account creation. Shows the four capabilities this build offers (Edge gateway, Machine discovery, Expose services, Health & monitoring) and marks `onboarded` in `auth.json`.

### Dashboard value obfuscation
A dashboard-wide obfuscation toggle masks IPs, MACs, and other sensitive values in the LiveView — useful for screen-sharing or recording.

---

## What it does NOT do (explicitly out of scope)

- **Wi-Fi bridging and all wireless management.** Wired only.
- **zrok / OpenZiti integration and public/private shares.**
- **WireGuard mesh / relay coordinator.** (A previous WireGuard mesh was removed; a per-machine WireGuard **overlay** is used instead so remote machines are reached directly.)
- **Local PKI on the LAN, and TLS anywhere.** Caddy listens on plain `http://` port 18000; every server tunneld emits sets `automatic_https: disable`, so nothing is ever ACME-provisioned.
- **Automatic config generation beyond the resource pool model.** Caddy configs are reconciled only for resources in `resources.json`.
- **CLI quick-share beyond the device-facing API.** Quick Expose is the only share endpoint.
- **Off-LAN / internet exposure of resources.** Operator-managed, separate from tunneld.
- **Non-Linux host management via a Linux VM.** Documented as a future direction but not implemented; only Linux hosts reachable over SSH (`kind: "host"`) are supported.
- **WebAuthn / passkey login.** Listed in the project structure as a future addition; auth today is bcrypt + session.

---

## Architecture

| Component | Role |
|-----------|------|
| `dnsmasq` | DHCP server + DNS resolver (forwarding + `*.tunneld.lan` named resolution) |
| `caddy` | Gateway-side reverse proxy with per-resource upstream load balancing — two planes: the LAN server on `0.0.0.0:18000` and a per-resource loopback listener |
| `iptables` | NAT, packet forwarding, DNS interception between `:upstream` and `:downstream` |
| `SSH` | Transport to managed machines (ControlMaster multiplexing, per-machine Ed25519 keys) |
| `WireGuard` | Overlay so remote machines are reachable as local IPs |
| `Elixir/Phoenix` | Application server, LiveView dashboard, GenServer process management |

### Supervision tree
One `one_for_one` supervisor (`Tunneld.Supervisor`) starts Telemetry, DNSCluster, PubSub, the Endpoint, and the domain servers: Session, SystemResources, Services, Resources, Devices, Auth, DnsConfig, Updater, AgentTokens, Jobs, and Geolocation. `Tunneld.Machines` is **not** a supervised child — it is a plain module, and `Machines.recover_all/0` runs once in a `Task` after the tree is up. Mock mode starts no extra process either: `Tunneld.Machines.SSH.Mock` is a plain module that `SSH.run/3` dispatches to.

### Diagrams
Detailed architecture diagrams with Mermaid (rendered on GitHub):
- [Network Topology](docs/network-topology.md) — How Tunneld bridges the upstream and downstream ethernet interfaces
- [Supervision Tree](docs/supervision-tree.md) — OTP process map, polling intervals, and PubSub topics

---

## Configuration

### Environment variables (production)
Set by the installer in the `tunneld.service` systemd unit:

| Variable | Description |
|----------|-------------|
| `UPSTREAM_INTERFACE` | Internet-facing NIC (selected at install time) |
| `DOWNSTREAM_INTERFACE` | LAN-facing NIC (selected at install time) |
| `GATEWAY` | Gateway IP for the downstream subnet (e.g. `10.0.0.1`) |
| `DEVICE_ID` | Unique device identifier (UUID) |
| `SECRET_KEY_BASE` | Phoenix signing key (generated at install time) |
| `PORT` | HTTP port for the dashboard (default `80`) |

### Dev/test config
Interface names default to `eth0` / `eth1` in `config/dev.exs` and `config/test.exs`. Mock mode is on by default in both. The LAN domain (`tunneld.lan`) and listen port (`18000`) are module attributes in `Tunneld.Caddy`.

### Persistent state
All state is JSON files under `TUNNELD_DATA` (prod: `/var/lib/tunneld`, dev: `data/`). Writes are atomic (write to temp file, rename) with `.bak` recovery on read.

| File | Purpose |
|------|---------|
| `auth.json` | bcrypt admin credentials + onboarding flag |
| `resources.json` | Resource registry (name, pool, kind) |
| `machines.json` | Enrolled machines (id, name, address, ssh_port, kind, location, capabilities) |
| `dns.json` | Upstream DNS server IP |
| `device_tags.json` | Device friendly-name tags (MAC → labels) |
| `expose_allowed.json` | Quick Expose per-device allowlist (MAC → boolean) |
| `tokens.json` | Agent API tokens (SHA-256 hashes + scopes) |
| `overlay.json` | WireGuard overlay IP allocations per machine |
| `egress_tables.json` | Routing-table numbers assigned to exit machines |
| `device_egress.json` | Per-device egress selections (device IP → exit machine) |
| `audit.jsonl` | Append-only JSON-lines audit log of agent API calls |

Machine SSH private keys are stored per-machine under `TUNNELD_DATA/ssh/<machine_id>` (mode 0600); WireGuard keys live under `TUNNELD_DATA/wg/<machine_id>`.

---

## Installation

Tunneld is designed for Debian-based SBCs such as Raspberry Pi, NanoPi, or any custom ARM64 setup.

```bash
curl -sSf https://raw.githubusercontent.com/toreanjoel/tunneld-installer/main/install.sh | sudo bash
```

The installer handles all dependencies: `dnsmasq`, `dhcpcd`, `caddy`, `iptables`, and `openssl`. It prompts you to select your upstream and downstream interfaces from a list of detected NICs, then writes a systemd unit that passes `UPSTREAM_INTERFACE` and `DOWNSTREAM_INTERFACE` to the app. It also wires dnsmasq to resolve `*.tunneld.lan` names to the gateway so named resources are reachable across the subnet. No Wi-Fi, Zrok, or VPN setup steps.

> **Note**: The installer lives in a separate repo ([tunneld-installer](https://github.com/toreanjoel/tunneld-installer)) and has been updated alongside this rework.

---

## Project structure

```
lib/
  tunneld/
    application.ex          # OTP supervision tree
    config.ex               # Shared config helpers
    net_link.ex             # Ethernet link state (reads /sys/class/net/<iface>/operstate)
    geolocation.ex          # IP geolocation GenServer with PubSub broadcasts
    iptables.ex             # iptables firewall rule management
    persistence.ex          # Atomic JSON file persistence with .bak recovery
    machines.ex             # Machine registry + SSH-backed control plane
    machines/
      store.ex              # machines.json persistence
      ssh.ex                # SSH transport (Ed25519 keys, ControlMaster)
      ssh/mock.ex           # Simulated SSH target for dev
      ssh/session.ex        # Interactive PTY over Erlang :ssh (browser terminal)
      runtime.ex            # Runtime-agnostic listeners (ss -tlnp) + generic probe
    geo_data/
      world_map.ex          # Inline SVG world map (offline, no CDN)
    schema.ex               # Schema definitions for configuration forms
    schema/                 # JSON Schema defs driving dynamic modal forms
    servers/
      session.ex            # In-memory IP-keyed auth sessions
      auth.ex               # bcrypt admin credentials + onboarding flag
      resources.ex          # Resource registry (CRUD, Caddy config, pool health every 10s)
      devices.ex            # DHCP lease monitoring, tagging, and revocation
      services.ex           # systemd service monitoring (dnsmasq, dhcpcd, caddy)
      dns_config.ex         # DNS upstream server configuration (user-selectable)
      updater.ex            # OTA update checking (polls GitHub for new releases)
      system_resources.ex   # CPU, memory, disk, and CPU temperature monitoring
      expose_allowed.ex     # Quick Expose per-device allowlist
      device_tags.ex        # Device friendly-name tags
      fake_data.ex          # Mock data for dev mode
  tunneld_web/
    live/
      dashboard.ex          # Main dashboard LiveView
      dashboard/actions.ex  # Action dispatcher
      setup.ex              # First-run setup wizard
      login.ex              # Login/signup
      components/           # LiveView components (machines, resources, devices, terminal, obfuscation, etc.)
    channels/
      user_socket.ex        # Phoenix socket for the exec terminal channel
      exec_channel.ex       # Streams an interactive SSH shell to the browser terminal
    controllers/
      device_controller.ex  # Device-facing read API (/api/v1/device/*)
      expose_controller.ex  # Quick Expose API (/api/v1/expose)
      machine_controller.ex # Admin machine endpoints (public key download, etc.)
      health_controller.ex  # Health endpoint
```

---

## Development

Run Tunneld locally with mocked hardware interactions:

1. Install Elixir and Erlang/OTP — `.tool-versions` pins `elixir 1.18.3-otp-26` / `erlang 26.2.5` (CI uses the same pair); `mix.exs` requires `~> 1.17`
2. Install dependencies: `mix deps.get`
3. Install JS/CSS tooling: `mix assets.setup`
4. Start the server: `mix phx.server`

Mock data is enabled by default in dev via `config/dev.exs`. Visit `localhost:80` in your browser.

In mock mode (`MOCK_DATA=true`) no system commands are executed — `systemctl`, `iptables`, sysfs reads, and SSH are all stubbed. Ethernet link state comes from `Tunneld.Servers.FakeData.ethernet/0`, DHCP leases from `FakeData.devices/0`, and a fake SSH target is simulated via `Tunneld.Machines.SSH.Mock` so the full enroll → probe → list loop works on a laptop. This lets you develop the full application on macOS, Linux, or any platform with Elixir installed.

### Running tests

```bash
mix test
```

Tests cover the NetLink helper, machine enrollment, Runtime listeners, Overlay, Egress, Reconcile, and the agent API. Tests that modify Application env use `async: false`.

### Version management

```bash
mix version          # show current version
mix version patch    # bump patch (0.10.5 -> 0.10.6)
mix version minor    # bump minor (0.10.5 -> 0.11.0)
mix version major    # bump major (0.10.5 -> 1.0.0)
```

Updates both `mix.exs` and `config/config.exs`.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on setting up your dev environment, running tests, and submitting changes.

## License

[Apache 2.0](LICENSE)