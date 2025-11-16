# Tunneld

A wireless-first, zero-trust network manager built for portability, performance, and total control. Spend less time on infrastructure and more time building without giving up security.

---

Tunneld acts as your network's intelligent gateway — managing devices, assigning IPs via DHCP, resolving DNS securely, sharing local compute and exposing optional network services through Zrok Tunnels. Designed to be lightweight, modular, and resource-driven, Tunneld works both at home and on the move. The goal, you focus on building and can plug the device in your network, keeping it isolated and allowing you expose and resource resources publicly or private over a private tunneld network.

---

## ✨ Features

### 🔐 Zero Trust Network Access
Tunneld treats every device as untrusted by default. Access to the internet is explicitly granted — no open gateway, no assumptions. Devices are approved manually.

### 📡 Wireless-First Design
Built to operate by wirelessly connecting to upstream internet source, Tunneld runs independently from your router or ISP equipment. Devices connect directly to Tunneld's and receive configuration, access control, and internet routing through its ethernet interface.
Everything you need can be controlled through the tunneld dashboard

### 🧠 Intelligent DHCP + DNS + DNScrypt
- Acts as the **DHCP server** for your network
- Uses `dnsmasq` for fast, cache-aware DNS resolution
- Integrates DNS-over-HTTPS (DoH) to block ads, tracking domains, and fingerprinting 
- Ensures all DNS queries are filtered and resolved securely

### 📡 Local & Remote Resource Monitoring
Tunneld monitors active services (e.g., dnsmasq, doh proxy) and connected devices. It also allows you to setup resources that setup intent to potentially sharing a resource that exists on some machine on your tunneld network.

### 🌍 Zrok Tunnel First class citizen
Expose your local Tunneld UI or custom services to the internet via secure Zrok Tunnels. Great for accessing your dashboard while away from home, self host applications running on any device on its network, or connecting peer tunneld instances together.

### 🖥️ Optional Compute sharing
Tunneld is the gateway, once setting up nodes to be montored, you can resource compute between Tunneld devices through APIs, sharing local services to trusted parites i.e AI APIs access etc. that others can access through their Tunneld Host

### 🧩 Static or Portable
Run Tunneld in:
- **Static mode**: At home, replacing your router's weak UI — manage every device, filter content, and control network flow.
- **Portable mode**: Take it with you. Resource access, deploy temporary networks, or integrate Tunneld with mobile data.

---

## 🧬 Core Architecture

| Component        | Description                                                                 |
|------------------|-----------------------------------------------------------------------------|
| `dnsmasq`        | DHCP and DNS resolution with caching and ad blocking                       |
| `dnscrypt-proxy` | Enforces DNS-over-HTTPS (DoH) with preloaded secure resolvers              |
| `Elixir + Phoenix` | Manages the UI, session-based device approval, sahre discovery, and services |
| `iptables`       | Controls packet forwarding and filtering                                    |
| `Zrok/OpenZiti`    | The tunnel provider that will be orchestrated through the tool              |

---

## 🔧 UI Overview

- Approve or deny internet access per device
- See service status and restart components if needed
- Dynamic refresh — minimal design, efficient interaction
- Creating Resources (references with intent to resource and monitor for any selfhosted application on its network)
- Expose Services to the internet using Zrok tunnels
- Enable sharing and connect to other tunneld devices to access shared/enabled resources
- Tunneld sends device health and overview information to a device on its network (get events when activity takes place)

---

## ⚙️ Deployment

You can deploy Tunneld to:
- Raspberry Pi
- NanoPi
- Custom Debian-based OS SBCs (Current using Armbian)
- [Insert any ARM + debian based SBC setup] etc

Install via install script that will walk through the entire setup with all needed dependencies. You can also build from source.
---

## 🌐 Local API

Tunneld exposes endpoints for:
- Getting current tunneld instance overview details (Internal health and monitoring)
- Resource registration and schema-based contract sharing over tunneld private network

> This allows custom nodes (AI inference, file servers, etc.) to announce themselves and expose UIs or APIs back to Tunneld.

---

## 🛠 Admin Philosophy

Tunneld is built for users who:
- Want **control without overhead** exposing services, resources and compute without firewall punching
- Need a plug and play installation to self host on a debian based OS and SBC
- Want to focus on building instead of infrastructure (being your own private cloud)

---

## 🧪 Example Use Cases

- Connect a router in bridge mode to expand tunneld device network to be accessed wirelessly
- Distributed compute and application exposing and sharing across households or friends (hosting blogs, website etc)
- Network level ad blocking
- Secure DNS encryption
- Access to your APIs and tools over a trusted application level encrypted network (your own compute or friends sharing APIs)

> [Install Script](https://github.com/toreanjoel/tunneld-installer)
