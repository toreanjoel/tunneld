# Tunneld

![CI Status](https://img.shields.io/badge/build-passing-brightgreen)
![Elixir](https://img.shields.io/badge/elixir-1.18+-purple)
![Phoenix](https://img.shields.io/badge/phoenix-1.7+-orange)
![Nginx](https://img.shields.io/badge/nginx-1.18+-green)
![Zrok](https://img.shields.io/badge/zrok-enabled-blue)
![Platform](https://img.shields.io/badge/platform-debian-red)

A wireless-first software-defined gateway for ARM single-board computers. Tunneld bridges Wi-Fi and Ethernet to create a private subnet, manages devices via DHCP, resolves DNS securely, reverse-proxies local services with auto-SSL, and optionally exposes them through Zrok overlay tunnels.

Designed to be lightweight and portable — run it at home as a smarter router, or take it anywhere as a self-contained network appliance.

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

### Local PKI & Auto-SSL
Generates a Root CA on first run. Every resource gets a TLS certificate signed by your CA, served through nginx. Install the Root CA on your devices for trusted HTTPS across your subnet.

### Secure DNS
All DNS queries are intercepted and routed through `dnscrypt-proxy` with DNS-over-HTTPS. Includes a DNS sinkhole (via dnsmasq blocklists) for ad and tracker blocking at the network level.

### Resource Management & Health Monitoring
Define resources that point to services running on your subnet. Each resource has a pool of backends that are health-checked via TCP probes. Nginx load-balances across healthy backends with auto-generated configs.

### Overlay Networking (Zrok/OpenZiti)
Expose resources publicly or privately through Zrok tunnels without port forwarding. Share services across Tunneld instances — bind remote shares locally and add them to your nginx pool for distributed load balancing.

### Distributed Service Pooling
Combine local and remote backends in a single resource pool. Nginx distributes traffic across all entries — whether they're on your subnet or bound from a peer's Tunneld instance over the overlay.

### AI Assistant
Chat with an AI assistant to manage your gateway. Supports any OpenAI-compatible API (Ollama recommended for privacy). The assistant can read status, manage resources, and perform actions through natural language. Accessible via a floating button on the dashboard when configured.

### First-Run Setup Wizard
Guided onboarding flow after initial account creation: connect to Wi-Fi, optionally configure the overlay network control plane, and optionally connect an AI provider.

## Architecture

| Component | Role |
|-----------|------|
| `dnsmasq` | DHCP server + DNS resolver with caching and blocklist filtering |
| `dnscrypt-proxy` | DNS-over-HTTPS enforcement with secure resolvers |
| `nginx` | Reverse proxy with per-resource SSL and upstream load balancing |
| `iptables` | NAT, packet forwarding, and DNS interception |
| `Zrok v2/OpenZiti` | Overlay tunnel orchestration (namespace names, share, access) |
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

The installer handles all dependencies: `dnsmasq`, `dhcpcd`, `nginx`, `iptables`, `dnscrypt-proxy`, and `zrok2`.

## Project Structure

```
lib/
  tunneld/
    application.ex          # OTP supervision tree
    config.ex               # Shared config helpers
    persistence.ex          # Atomic JSON file persistence with backup recovery
    iptables.ex             # iptables firewall rule management
    cert_manager.ex         # SSL certificate lifecycle (root CA + per-resource)
    servers/
      session.ex            # In-memory IP-keyed auth sessions
      auth.ex               # Login credentials (bcrypt + WebAuthn)
      resources.ex          # Resource registry (CRUD, Zrok shares, nginx, DNS)
      resources/health.ex   # Pool backend health checking (TCP probes)
      devices.ex            # DHCP lease monitoring and revocation
      services.ex           # systemd service monitoring (dnsmasq, dhcpcd, etc.)
      wlan.ex               # Wi-Fi interface management (wpa_supplicant)
      nginx.ex              # Nginx reverse proxy config generation
      dnsmasq.ex            # DNS hairpin entry management
      zrok.ex               # Zrok v2 CLI orchestration (names, shares, access units)
      blocklist.ex          # DNS sinkhole blocklist management
      sqm.ex                # Smart Queue Management (tc/CAKE)
      updater.ex            # OTA update checking
      system_resources.ex   # CPU, memory, disk monitoring
      ai.ex                 # AI provider config management
      chat.ex               # Chat session state and tool-use loop
    ai/
      client.ex             # OpenAI-compatible API client
      tools.ex              # Tool definitions for AI actions
      executor.ex           # Bridges tool calls to dashboard actions
      system_prompt.ex      # AI system prompt generation
    schema/                 # JSON Schema validation (login, signup, resource, wlan, zrok)
  tunneld_web/
    live/
      dashboard.ex          # Main dashboard LiveView
      dashboard/actions.ex  # Action dispatcher
      setup.ex              # First-run setup wizard
      login.ex              # Login/signup with WebAuthn support
      components/           # LiveView components (devices, resources, services, sidebar, chat, etc.)
```

## Development

Run Tunneld locally with mocked hardware interactions:

1. Install Elixir 1.18+ and Erlang/OTP 27+
2. Install dependencies: `mix deps.get`
3. Install JS/CSS tooling: `mix assets.setup`
4. Start the server: `MOCK_DATA=true mix phx.server`

Visit `localhost:4000` in your browser.

The `MOCK_DATA=true` flag stubs all system commands (systemctl, wpa_cli, iw, tc, etc.) with fake data so you can develop on any OS without hardware.

### Running Tests

```bash
MOCK_DATA=true mix test
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
