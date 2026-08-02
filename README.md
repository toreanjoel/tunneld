# Tunneld

![CI Status](https://img.shields.io/badge/build-passing-brightgreen)
![Elixir](https://img.shields.io/badge/elixir-1.18+-purple)
![Phoenix](https://img.shields.io/badge/phoenix-1.7+-orange)
![Nginx](https://img.shields.io/badge/nginx-1.18+-green)
![Platform](https://img.shields.io/badge/platform-debian-red)

Software for a dual-NIC ARM64 single-board computer that turns it into a wired edge gateway for a private subnet, plus a fleet manager for Incus containers and VMs running on machines it reaches over SSH. Two capabilities, one relationship: the gateway owns the network, and the instances it manages live on or are reachable from that network.

Each node is self-contained (no database - just JSON files) and runs on a small ARM64 SBC. Plug devices into the downstream port, manage them from a real-time LiveView dashboard, and provision Incus instances on machines you've enrolled over SSH.

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
Track all devices on the subnet via DHCP leases with real-time online status indicators (ping probe, cached 30s). Tag devices for organization. Revoke DHCP leases to force devices off the network.

### Fleet Management (Machines + Incus)
Enroll machines (local subnet devices or remote VPSes) that expose a Linux SSH endpoint. Tunneld generates an Ed25519 keypair per machine, displays the public half for you to install on the target, probes capabilities over SSH, and can create, start, stop, list, and delete Incus containers and VMs. Host specs (CPU, memory, storage, architecture, KVM, GPU) are surfaced per target. State is queried live over SSH; the target is the source of truth. Non-Linux hosts are managed via a Linux VM on that host.

- **Local targets** should use `macvlan` so containers get leases directly from Tunneld's dnsmasq and appear as normal subnet devices.
- **Remote targets** use a NAT bridge; reaching an app inside a container requires a manually configured reverse proxy on the target host.

### Interactive Shell (Incus exec)
Open a browser terminal into a container or VM over the Phoenix channel `exec:<machine>:<container>`, streaming `incus exec` over SSH with a PTY. Keypresses flow from the browser to the SSH stdin in real time.

### Expose Remote Container Services to the Subnet
macvlan only spans a single Layer-2 segment, so a container on a machine reached over the internet cannot appear as a subnet device. For **remote** machines, tunneld instead opens a reverse SSH port-forward from the gateway to the container's port, then registers an nginx resource whose pool points at the forwarded port. The container service becomes reachable subnet-wide at `http://<name>.tunneld.lan:18000`, indistinguishable from a local service. In the dashboard, remote containers show an **Expose** button where you enter the container's port.

- **Local targets**: prefer macvlan so the container gets its own DHCP lease and subnet IP (a first-class subnet device).
- **Remote targets**: use the reverse-SSH expose for service-level reachability; the container itself stays NAT'd behind the host.

### Device-Facing Read API
Any device with a DHCP lease from this gateway can query machine, container, health, and exposure data without logging in (same device-resolution model as Quick Expose). Useful for CLI/scripts on subnet devices:

```
GET /api/v1/device/machines                  list machines + status + capabilities
GET /api/v1/device/machines/:id              machine detail + health
GET /api/v1/device/machines/:id/containers   list containers on a machine (live)
GET /api/v1/device/resources                 list exposed resources (incl. remote exposures)
GET /api/v1/device/health                    gateway + service status
```

For example: `curl http://<gateway>/api/v1/device/machines`. The `/api/v1/machines*` (admin) endpoints remain password-protected for provisioning and lifecycle management.

### Geolocation
The dashboard surfaces the gateway's public IP geolocation. Device location is determined from the public IP and displayed on the dashboard.

### First-Run Setup Wizard
Guided onboarding flow after initial account creation.

## Architecture

| Component | Role |
|-----------|------|
| `dnsmasq` | DHCP server + DNS resolver forwarding to user-configured upstream |
| `nginx` | Reverse proxy (optional) |
| `iptables` | NAT, packet forwarding, and DNS interception between `:upstream` and `:downstream` |
| `Elixir/Phoenix` | Application server, LiveView dashboard, GenServer process management |
| `SSH` | Transport to managed machines (ControlMaster multiplexing, per-machine Ed25519 keys) |
| `Incus` | Container/VM provider on managed machines |

### Diagrams

Detailed architecture diagrams with Mermaid (rendered on GitHub):

- [Network Topology](docs/network-topology.md) - How Tunneld bridges the upstream and downstream ethernet interfaces
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
| `machines.json` | Enrolled machines (id, name, address, ssh_port, kind, capabilities) |
| `dns_config.json` | Upstream DNS server IP |

Machine SSH private keys are stored per-machine under `TUNNELD_DATA/ssh/<machine_id>` (mode 0600).

Writes are atomic (write to temp file, rename) with `.bak` recovery on read.

## Installation

Tunneld is designed for Debian-based SBCs such as Raspberry Pi, NanoPi, or any custom ARM64 setup.

```bash
curl -sSf https://raw.githubusercontent.com/toreanjoel/tunneld-installer/main/install.sh | sudo bash
```

The installer handles all dependencies: `dnsmasq`, `dhcpcd`, `nginx`, `iptables`, and `openssl`. It prompts you to select your upstream and downstream interfaces from a list of detected NICs, then writes a systemd unit that passes `UPSTREAM_INTERFACE` and `DOWNSTREAM_INTERFACE` to the app. It also wires dnsmasq to resolve `*.tunneld.lan` names to the gateway so named resources are reachable across the subnet. No Wi-Fi, Zrok, or VPN setup steps.

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
      machines.ex             # Machine registry + SSH-backed Incus control plane
      machines/
        store.ex              # machines.json persistence
        ssh.ex                # SSH transport (Ed25519 keys, ControlMaster)
        ssh/mock.ex           # Simulated Incus target for dev
        provider.ex           # Incus provider dispatch (probe/list/create/start/stop/delete)
        exec.ex               # Interactive incus exec over SSH, streamed to browser
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
        updater.ex            # OTA update checking
        system_resources.ex   # CPU, memory, disk monitoring
  tunneld_web/
    live/
      dashboard.ex            # Main dashboard LiveView
      dashboard/actions.ex    # Action dispatcher
      setup.ex                # First-run setup wizard
      login.ex                # Login/signup with WebAuthn support
      components/             # LiveView components (machines, resources, devices, terminal, etc.)
    channels/
      user_socket.ex          # Phoenix socket for the exec terminal channel
      exec_channel.ex         # Streams incus exec to the browser terminal
```

## Development

Run Tunneld locally with mocked hardware interactions:

1. Install Elixir 1.18+ and Erlang/OTP 26+
2. Install dependencies: `mix deps.get`
3. Install JS/CSS tooling: `mix assets.setup`
4. Start the server: `mix phx.server`

Mock data is enabled by default in dev via `config/dev.exs`. Visit `localhost:80` in your browser.

In mock mode (`MOCK_DATA=true`) no system commands are executed - `systemctl`, `iptables`, sysfs reads, and SSH are all stubbed. Ethernet link state comes from `Tunneld.Servers.FakeData.ethernet/0`, DHCP leases from `FakeData.devices/0`, and a fake Incus target is simulated via `Tunneld.Machines.SSH.Mock` so the full enroll -> probe -> provision -> exec loop works on a laptop. This lets you develop the full application on macOS, Linux, or any platform with Elixir installed.

### Running Tests

```bash
mix test
```

Tests cover the NetLink helper, machine enrollment, Incus provider/provisioning lifecycle, and interactive exec. Tests that modify Application env use `async: false`.

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
