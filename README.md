# Tunneld

![CI Status](https://img.shields.io/badge/build-passing-brightgreen)
![Elixir](https://img.shields.io/badge/elixir-1.18+-purple)
![Phoenix](https://img.shields.io/badge/phoenix-1.7+-orange)
![Nginx](https://img.shields.io/badge/nginx-1.18+-green)
![Zrok](https://img.shields.io/badge/zrok-enabled-blue)
![Platform](https://img.shields.io/badge/platform-debian-red)

A wireless-first, zero-trust programable gateway built for portability, performance, and total control. Spend less time on infrastructure and more time building without giving up security.

Tunneld acts as your network's intelligent gateway — managing devices, assigning IPs via DHCP, resolving DNS securely, sharing local compute, and exposing optional network services through Zrok Tunnels. Designed to be lightweight, modular, and resource-driven, Tunneld works both at home and on the move. The goal is to let you focus on building while Tunneld handles the network, keeping devices isolated and allowing you to expose resources publicly or privately over a secure network.

> **Prerequisites**
>
> Before you begin, ensure you have the following:
> - **Zrok Access**: A self-hosted Zrok control plane or an account with Zrok.
> - **Hardware**: An ARM-based Single Board Computer (SBC) equipped with both **wireless** and **ethernet** interfaces.
> - **Operating System**: A Debian-based OS.
> - **Connectivity Note**: The device currently only supports upstream internet access via the **Wi-Fi interface**.

## Features

### Zero Trust Network Access
Tunneld treats every device as untrusted by default. Access to the internet is explicitly granted — no open gateway, no assumptions. Devices are approved manually.

### Wireless-First Design
Built to operate by wirelessly connecting to an upstream internet source, Tunneld runs independently from your router or ISP equipment. Devices connect directly to Tunneld's downstream interface and receive configuration, access control, and internet routing. Everything can be controlled through the Tunneld dashboard.

### Intelligent DHCP, DNS, and DNScrypt
- Acts as the **DHCP server** for your network.
- Uses `dnsmasq` for fast, cache-aware DNS resolution.
- Integrates `dnscrypt-proxy` to enforce DNS-over-HTTPS (DoH), blocking ads, tracking domains, and fingerprinting.
- Ensures all DNS queries are filtered and resolved securely using providers like Mullvad DoH.

### Local and Remote Resource Monitoring
Tunneld monitors active services (e.g., dnsmasq, DoH proxy) and connected devices. It also allows you to setup resources that define an intent to share a service existing on a machine within your Tunneld network.

### Zrok Tunnel Integration
Expose your local Tunneld UI or custom services to the internet via secure Zrok Tunnels. Great for accessing your dashboard while away from home, self-hosting applications running on any device on the network, or connecting peer Tunneld instances together.

### Compute Sharing
Tunneld acts as a gateway. Once nodes are set up to be monitored, you can share compute resources between Tunneld devices through APIs, allowing trusted parties to access local services (e.g., AI APIs) through their Tunneld Host.

### Deployment Modes
Run Tunneld in:
- **Static mode**: At home, replacing your router's weak UI — manage every device, filter content, and control network flow.
- **Portable mode**: Take it with you. Manage resource access, deploy temporary networks, or integrate Tunneld with mobile data.

## Core Architecture

| Component        | Description                                                                 |
|------------------|-----------------------------------------------------------------------------|
| `dnsmasq`        | DHCP and DNS resolution with caching and ad blocking.                       |
| `dnscrypt-proxy` | Enforces DNS-over-HTTPS (DoH) with secure resolvers.                        |
| `Elixir + Phoenix` | Manages the UI, session-based device approval, discovery, and services.     |
| `iptables`       | Controls packet forwarding and filtering.                                   |
| `Zrok/OpenZiti`  | The tunnel provider orchestrated through the tool.                          |
| `Nginx`          | Reverse proxy to manage access to the dashboard and resources.              |

## Dashboard Features

- View service status and restart components if needed.
- Dynamic refresh with a minimal, efficient design.
- Create Resources (references with intent to share and monitor self-hosted applications).
- Expose Services to the internet using Zrok tunnels.
- Enable sharing and connect to other Tunneld devices to access shared resources.
- Updates for the built-in Open Source DNS sinkhole.
- Load balance resource instances across local or distributed instances with trusted parties.

## Installation

Tunneld is designed for Debian-based SBCs (Single Board Computers) such as:
- Raspberry Pi
- NanoPi
- Custom Debian-based setups

The installation script handles dependencies including `dnsmasq`, `dhcpcd`, `nginx`, `iptables`, `dnscrypt-proxy`, and `zrok`.

### Install Script

```bash
curl -sSf https://raw.githubusercontent.com/toreanjoel/tunneld-installer/main/install.sh | sudo bash
```

## Development

To run Tunneld locally for development (mocking hardware interactions):

1.  Install dependencies: `mix deps.get`
2.  Start the server: `MOCK_DATA=true mix phx.server`

Now you can visit `localhost:4000` from your browser.

## API Access

Tunneld exposes endpoints for:
- Getting current Tunneld instance overview details (Internal health and monitoring).
- Resource registration and schema-based contract sharing over the private network.

This allows custom nodes (AI inference, file servers, etc.) to announce themselves and expose UIs or APIs back to Tunneld.

## Philosophy

Tunneld is built for users who:
- Want **control without overhead** when exposing services, resources, and compute without firewall punching.
- Need a plug-and-play installation to self-host on a Debian-based OS.
- Want to focus on building instead of infrastructure (being your own private cloud).
- Wish to share resources with trusted individuals in a distributed manner.

## Use Cases

- Connect a router in bridge mode to expand the Tunneld device network wirelessly.
- Distributed compute and application sharing across households or friends (hosting blogs, websites, etc.).
- Network-level ad blocking.
- Secure DNS encryption.
- Access to APIs and tools over a trusted application-level encrypted network.
