# Tunneld

![CI Status](https://img.shields.io/badge/build-passing-brightgreen)
![Elixir](https://img.shields.io/badge/elixir-1.18+-purple)
![Phoenix](https://img.shields.io/badge/phoenix-1.7+-orange)
![Nginx](https://img.shields.io/badge/nginx-1.18+-green)
![Platform](https://img.shields.io/badge/platform-debian-red)

An ethernet-first private network edge relay for ARM single-board computers. Tunneld bridges an upstream internet link and a downstream ethernet port to create a private subnet, manages devices via DHCP, reverse-proxies local services over nginx, and connects to other Tunneld nodes via WireGuard mesh networking - all managed from a real-time LiveView dashboard.

Each node is self-contained (no database - just JSON files) and runs on a $35 Raspberry Pi. Plug devices into the downstream port, tag them for mesh access, and expose services to the subnet at `<name>.tunneld.lan`.

> **Prerequisites**
>
> - **Hardware**: An ARM64 SBC with two ethernet interfaces (Raspberry Pi, NanoPi, etc.)
> - **Operating System**: Debian-based OS
>
> Tunneld owns two NICs: one upstream (internet) and one downstream (your private subnet). It does not use Wi-Fi. Interface names are selected dynamically at install time and read from app config at runtime - never hardcoded.

## Features

### Ethernet-First Gateway
Connects upstream to the internet over one NIC and serves a private subnet over the other. Devices plug into the downstream port and receive IPs, DNS, and internet access - no existing router UI needed. Link state for both interfaces is read on demand from `/sys/class/net/<iface>/operstate` by `Tunneld.NetLink` (no GenServer, no polling). Everything is controlled through the Tunneld dashboard.

### DNS Forwarding
DNS queries on the subnet are intercepted via iptables and forwarded to a user-configured upstream DNS server. Select any resolver from the dashboard - Cloudflare (1.1.1.1), Google (8.8.8.8), or a local Pi-hole on your network. Same-subnet DNS servers are supported via automatic prerouting rules.

### Device Management
Track all devices on the subnet via DHCP leases with real-time online status indicators (ping probe, cached 30s). Tag devices for organization and mesh exposure (tags with the `wg` prefix advertise a device to the mesh network). Revoke DHCP leases to force devices off the network.

### Resource Management & Health Monitoring
Define resources that point to services running on your subnet. Each resource has a pool of backends (`IP:port` entries) that are health-checked via TCP probes every 10 seconds. Nginx load-balances across healthy backends with auto-generated configs, and each resource is reachable from the subnet at `http://<name>.tunneld.lan:18000`. There is no public-internet exposure and no per-resource auth - access is limited to the local subnet; relay/mesh exposure is future work.

### Quick Expose
Devices on the subnet can create, list, and remove local resources with a single `curl`. The gateway resolves the caller from its DHCP lease, validates it against a per-device allowlist, and provisions a `<name>.tunneld.lan` hostname. Admin-controlled per-device allowlist grants or revokes this capability from the dashboard.

### Mesh Networking
Connect multiple Tunneld nodes into a single mesh through a relay coordinator. Each node registers outbound-only over WireGuard, receives a mesh IP, and syncs peers automatically. Tag LAN devices with `wg` prefix (e.g. `wg-printer`) to expose them to the mesh - no port forwarding required. The relay assigns virtual IPs via DNAT to avoid subnet collisions between nodes.

### World Map & Geolocation
The dashboard renders an offline 2D world map showing peer locations by country. Device geolocation is determined from the public IP and displayed as a pin on the map.

### First-Run Setup Wizard
Guided onboarding flow after initial account creation: optionally configure the mesh relay coordinator (relay URL, token, node name, WireGuard MTU).

## Architecture

| Component | Role |
|-----------|------|
| `dnsmasq` | DHCP server + DNS resolver forwarding to user-configured upstream |
| `nginx` | Reverse proxy with per-resource upstream load balancing (listens on `0.0.0.0:18000`) |
| `iptables` | NAT, packet forwarding, and DNS interception between `:upstream` and `:downstream` |
| `WireGuard` | Mesh networking interface (`wg-mesh`) for node-to-node connectivity via relay |
| `Elixir/Phoenix` | Application server, LiveView dashboard, GenServer process management |

### Diagrams

Detailed architecture diagrams with Mermaid (rendered on GitHub):

- [Network Topology](docs/network-topology.md) - How Tunneld bridges the upstream and downstream ethernet interfaces
- [Resource Lifecycle](docs/resource-lifecycle.md) - Creating, updating, and removing resources and their nginx configs
- [Distributed Load Balancing](docs/distributed-load-balancing.md) - Combining backends in nginx pools
- [Nginx & SSL](docs/nginx-ssl.md) - Certificate chain, config generation, and hairpin DNS
- [Supervision Tree](docs/supervision-tree.md) - OTP process map, polling intervals, and PubSub topics

## Configuration

### Environment Variables (Production)

Set by the installer in the `tunneld.service` systemd unit:

| Variable | Description |
|----------|-------------|
| `UPSTREAM_INTERFACE` | Internet-facing NIC (selected at install time) |
| `DOWNSTREAM_INTERFACE` | LAN-facing NIC (selected at install time) |
| `GATEWAY` | Gateway IP for the downstream subnet (e.g. `10.0.0.1`) |
| `DEVICE_ID` | Unique device identifier (UUID) |
| `SECRET_KEY_BASE` | Phoenix signing key (generated at install time) |
| `PORT` | HTTP port for the dashboard (default `80`) |

### Dev/Test Config

Interface names default to `eth0` / `eth1` in `config/dev.exs` and `config/test.exs`. Mock mode is on by default in both. The LAN domain (`tunneld.lan`) and nginx listen port (`18000`) are module attributes in `Tunneld.Servers.Nginx`.

### Persistent State

All state is JSON files under `TUNNELD_DATA` (prod: `/var/lib/tunneld`, dev: `data/`):

| File | Purpose |
|------|---------|
| `auth.json` | bcrypt admin credentials + onboarding flag |
| `resources.json` | Resource registry (name, pool, kind) |
| `mesh_config.json` | Mesh relay config (coordinator URL, token, node name) |
| `mesh_node_id.json` | Persistent mesh node UUID |
| `wireguard.json` | WireGuard keypair |
| `dns_config.json` | Upstream DNS server IP |

Writes are atomic (write to temp file, rename) with `.bak` recovery on read.

## Installation

Tunneld is designed for Debian-based SBCs such as Raspberry Pi, NanoPi, or any custom ARM64 setup.

```bash
curl -sSf https://raw.githubusercontent.com/toreanjoel/tunneld-installer/main/install.sh | sudo bash
```

The installer handles all dependencies: `dnsmasq`, `dhcpcd`, `nginx`, `iptables`, and `wireguard-tools`. It prompts you to select your upstream and downstream interfaces from a list of detected NICs, then writes a systemd unit that passes `UPSTREAM_INTERFACE` and `DOWNSTREAM_INTERFACE` to the app. No Wi-Fi, Zrok, or VPN setup steps.

> **Note**: The installer lives in a separate repo ([tunneld-installer](https://github.com/toreanjoel/tunneld-installer)) and has been updated alongside this rework.

## Project Structure

```
lib/
  tunneld/
    application.ex          # OTP supervision tree
    config.ex               # Shared config helpers
    net_link.ex             # Ethernet link state helpers (upstream/downstream operstate)
    geolocation.ex          # IP geolocation GenServer with PubSub broadcasts
    iptables.ex             # iptables firewall rule management
    persistence.ex          # Atomic JSON file persistence with backup recovery
    geo_data/
      centroids.ex          # Country centroid coordinates (generated from Natural Earth)
      world_map.ex          # Inline SVG world map component (offline, no CDN)
    schema/
    schema.ex               # Schema definitions for configuration forms
    servers/
      session.ex            # In-memory IP-keyed auth sessions
      auth.ex               # Login credentials (bcrypt + WebAuthn)
      resources.ex          # Resource registry (CRUD, nginx config, pool health)
      devices.ex            # DHCP lease monitoring and revocation
      services.ex           # systemd service monitoring (dnsmasq, dhcpcd, nginx)
      nginx.ex              # Nginx reverse proxy config generation (per-resource server block)
      dns_config.ex         # DNS upstream server configuration (user-selectable)
      wireguard.ex          # WireGuard keypair and wg-mesh interface
      mesh.ex               # Mesh relay coordinator client
      updater.ex            # OTA update checking
      system_resources.ex   # CPU, memory, disk monitoring
  tunneld_web/
    live/
      dashboard.ex          # Main dashboard LiveView with world map
      dashboard/actions.ex  # Action dispatcher
      setup.ex              # First-run setup wizard (mesh relay)
      login.ex              # Login/signup with WebAuthn support
      components/           # LiveView components (map_pin, mesh_card, sidebar, etc.)
```

## Development

Run Tunneld locally with mocked hardware interactions:

1. Install Elixir 1.18+ and Erlang/OTP 26+
2. Install dependencies: `mix deps.get`
3. Install JS/CSS tooling: `mix assets.setup`
4. Start the server: `mix phx.server`

Mock data is enabled by default in dev via `config/dev.exs`. Visit `localhost:80` in your browser.

In mock mode (`MOCK_DATA=true`) no system commands are executed - `systemctl`, `iptables`, and sysfs reads are all stubbed. Ethernet link state comes from `Tunneld.Servers.FakeData.ethernet/0`, DHCP leases from `FakeData.devices/0`, and mesh state from `FakeData.mesh/0`. This lets you develop the full application on macOS, Linux, or any platform with Elixir installed.

### Running Tests

```bash
mix test
```

Tests cover the NetLink helper, WireGuard keypair management, and mesh reconfiguration. Tests that modify Application env use `async: false`.

### Version Management

```bash
mix version          # show current version
mix version patch    # bump patch (0.10.5 -> 0.10.6)
mix version minor    # bump minor (0.10.5 -> 0.11.0)
mix version major    # bump major (0.10.5 -> 1.0.0)
```

Updates both `mix.exs` and `config/config.exs`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on setting up your dev environment, running tests, and submitting changes.

## License

[Apache 2.0](LICENSE)
