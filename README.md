# Tunneld

![CI Status](https://img.shields.io/badge/build-passing-brightgreen)
![Elixir](https://img.shields.io/badge/elixir-1.18+-purple)
![Phoenix](https://img.shields.io/badge/phoenix-1.7+-orange)
![Nginx](https://img.shields.io/badge/nginx-1.18+-green)
![Zrok](https://img.shields.io/badge/zrok-enabled-blue)
![Platform](https://img.shields.io/badge/platform-debian-red)

A wireless-first software-defined gateway for ARM single-board computers. Tunneld bridges Wi-Fi and Ethernet to create a private subnet, manages devices via DHCP, reverse-proxies local services, exposes them through Zrok overlay tunnels, and connects to other Tunneld nodes via WireGuard mesh networking — all managed from a real-time LiveView dashboard.

Each node is self-contained (no database — just JSON files) and runs on a $35 Raspberry Pi. Plug devices into Ethernet, tag them for mesh access, wake them remotely, and expose services publicly or privately.

> **Prerequisites**
>
> - **Hardware**: An ARM64 SBC with both wireless and ethernet interfaces (Raspberry Pi, NanoPi, etc.)
> - **Operating System**: Debian-based OS
> - **Zrok** (optional): A self-hosted Zrok control plane or account for overlay networking

## Features

### Wireless-First Gateway
Connects upstream via Wi-Fi and serves a private subnet over Ethernet. Devices plug in and receive IPs, DNS, and internet access — no existing router UI needed. Everything is controlled through the Tunneld dashboard.

### Smart Queue Management (SQM)
Implements the CAKE algorithm to eliminate bufferbloat and reduce latency. Choose between latency-optimized, balanced, or no shaping — applied in real-time via `tc`.

### DNS Forwarding
DNS queries on the subnet are intercepted via iptables and forwarded to a user-configured upstream DNS server. Select any resolver from the dashboard — Cloudflare (1.1.1.1), Google (8.8.8.8), or a local Pi-hole on your network. Same-subnet DNS servers are supported via automatic prerouting rules.

### Device Management
Track all devices on the subnet via DHCP leases with real-time online status indicators (ping probe, cached 30s). Tag devices for organization and mesh exposure. Wake devices on the local network or on a remote mesh peer via Wake-on-LAN magic packets. Revoke DHCP leases to force devices off the network.

### Resource Management & Health Monitoring
Define resources that point to services running on your subnet. Each resource has a pool of backends that are health-checked via TCP probes. Nginx load-balances across healthy backends with auto-generated configs.

### Quick Expose
Devices on the subnet can create, list, and remove public Zrok shares with a single `curl`. The gateway resolves the caller from its DHCP lease and provisions a public URL. Admin-controlled per-device allowlist grants or revokes this capability from the dashboard.

### Overlay Networking (Zrok/OpenZiti)
Expose resources publicly or privately through Zrok tunnels without port forwarding. Share services across Tunneld instances — bind remote shares locally and add them to your nginx pool for distributed load balancing.

### Mesh Networking
Connect multiple Tunneld nodes into a single mesh through a relay coordinator. Each node registers outbound-only over WireGuard, receives a mesh IP, and syncs peers automatically. Tag LAN devices with `wg` prefix (e.g. `wg-printer`) to expose them to the mesh — no port forwarding required. The relay assigns virtual IPs via DNAT to avoid subnet collisions between nodes.

### World Map & Geolocation
The dashboard renders an offline 2D world map showing peer locations by country. Device geolocation is determined from the public IP and displayed as a pin on the map.

### Distributed Service Pooling
Combine local and remote backends in a single resource pool. Nginx distributes traffic across all entries — whether they're on your subnet or bound from a peer's Tunneld instance over the overlay.

### First-Run Setup Wizard
Guided onboarding flow after initial account creation: connect to Wi-Fi, optionally configure the overlay network control plane and mesh relay.

## Architecture

| Component | Role |
|-----------|------|
| `dnsmasq` | DHCP server + DNS resolver forwarding to user-configured upstream |
| `nginx` | Reverse proxy with per-resource upstream load balancing |
| `iptables` | NAT, packet forwarding, and DNS interception |
| `Zrok v2/OpenZiti` | Overlay tunnel orchestration (namespace names, share, access) |
| `WireGuard` | Mesh networking interface (`wg-mesh`) for node-to-node connectivity via relay |
| `Elixir/Phoenix` | Application server, LiveView dashboard, GenServer process management |

### Diagrams

Detailed architecture diagrams with Mermaid (rendered on GitHub):

- [Network Topology](docs/network-topology.md) — How Tunneld bridges Wi-Fi upstream and Ethernet downstream
- [Resource Lifecycle](docs/resource-lifecycle.md) — Creating resources, enabling public/private shares, binding remote access
- [Distributed Load Balancing](docs/distributed-load-balancing.md) — Combining local and remote backends in nginx pools
- [Nginx & SSL](docs/nginx-ssl.md) — Certificate chain, config generation, and hairpin DNS
- [Supervision Tree](docs/supervision-tree.md) — OTP process map, polling intervals, and PubSub topics

## Installation

Tunneld is designed for Debian-based SBCs such as Raspberry Pi, NanoPi, or any custom ARM64 setup.

```bash
curl -sSf https://raw.githubusercontent.com/toreanjoel/tunneld-installer/main/install.sh | sudo bash
```

The installer handles all dependencies: `dnsmasq`, `dhcpcd`, `nginx`, `iptables`, and `zrok2`.

## Project Structure

```
lib/
  tunneld/
    application.ex          # OTP supervision tree
    config.ex               # Shared config helpers
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
      resources.ex          # Resource registry (CRUD, Zrok shares, nginx, DNS, health)
      devices.ex            # DHCP lease monitoring and revocation
      services.ex           # systemd service monitoring (dnsmasq, dhcpcd, etc.)
      wlan.ex               # Wi-Fi interface management (wpa_supplicant)
      nginx.ex              # Nginx reverse proxy config generation
      dns_config.ex         # DNS upstream server configuration (user-selectable)
      zrok.ex               # Zrok v2 CLI orchestration (names, shares, access units)
      sqm.ex                # Smart Queue Management (tc/CAKE)
      wireguard.ex          # WireGuard keypair and wg-mesh interface
      mesh.ex               # Mesh relay coordinator client
      updater.ex            # OTA update checking
      system_resources.ex   # CPU, memory, disk monitoring
  tunneld_web/
    live/
      dashboard.ex          # Main dashboard LiveView with world map
      dashboard/actions.ex  # Action dispatcher
      setup.ex              # First-run setup wizard
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

No system commands (systemctl, wpa_cli, iw, tc, iptables, etc.) are executed in mock mode — all GenServers use fake data so you can develop on any OS without hardware.

### Running Tests

```bash
mix test
```

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
