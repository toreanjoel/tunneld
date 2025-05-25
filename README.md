# Project Sentinel

A wireless-first, zero-trust network manager built for portability, performance, and total control.

<img width="1506" alt="Project Sentinel Dashboard Overview" src="https://github.com/user-attachments/assets/9594dc07-d456-47b3-8e2e-ab62ca9c4011" />

---

Sentinel acts as your network's intelligent gateway — managing devices, assigning IPs via DHCP, resolving DNS securely, sharing local compute and exposing optional network services through Cloudflare Tunnels. Designed to be lightweight, modular, and instance-driven, Sentinel works both at home and on the move.

---

## ✨ Features

### 🔐 Zero Trust Network Access
Sentinel treats every device as untrusted by default. Access to the internet is explicitly granted — no open gateway, no assumptions. Devices are approved manually or programmatically and assigned TTL-based access.

### 📡 Wireless-First Design
Built to operate as a wireless access point, Sentinel runs independently from your router or ISP equipment. Devices connect directly to Sentinel's network and receive configuration, access control, and internet routing.

### 🧠 Intelligent DHCP + DNS
- Acts as the **DHCP server** for your network
- Uses `dnsmasq` for fast, cache-aware DNS resolution
- Integrates DNS-over-HTTPS (DoH) to block ads, tracking domains, and fingerprinting
- Ensures all DNS queries are filtered and resolved securely

### 🛠 Built-in Web Terminal
Includes a web-accessible terminal within the Sentinel UI, allowing local shell access directly from the browser — ideal for managing services, debugging, or extending functionality on the fly.

### 📡 Local & Remote Instance Monitoring
Sentinel monitors active services (e.g., dnsmasq, hostapd, doh proxy) and connected devices. It can detect other nodes on the network and remotely display their status, offering an overview of your distributed system.

### 🌍 Optional Cloudflare Tunnel Support
Expose your local Sentinel UI or custom services to the internet via secure Cloudflare Tunnels. Great for accessing your dashboard while away from home, or connecting peer Sentinels together.

### 🖥️ Optional Compute sharing
Sentinel is the gateway, once setting up nodes to be montored, you can share compute between Sentinel devices, sharing local services to trusted parites i.e File storage, AI Compute etc. that others can access through their Sentinel Host

### 🧩 Static or Portable
Run Sentinel in:
- **Static mode**: At home, replacing your router's weak UI — manage every device, filter content, and control network flow.
- **Portable mode**: Take it with you. Share access, deploy temporary networks, or integrate Sentinel with mobile data.

---

## 🧬 Core Architecture

| Component        | Description                                                                 |
|------------------|-----------------------------------------------------------------------------|
| `dnsmasq`        | DHCP and DNS resolution with caching and ad blocking                       |
| `hostapd`        | Broadcasts the wireless access point                                        |
| `dnscrypt-proxy` | Enforces DNS-over-HTTPS (DoH) with preloaded secure resolvers              |
| `Elixir + Phoenix` | Manages the UI, session-based device approval, instance discovery, and services |
| `iptables`       | Controls packet forwarding and filtering                                    |

---

## 🔧 UI Overview

- Approve or deny internet access per device
- View connected devices and their lease information
- See service status and restart components if needed
- View internal terminal output or issue commands directly
- Dynamic refresh — minimal design, efficient interaction

---

## ⚙️ Deployment

You can deploy Sentinel to:
- Raspberry Pi
- NanoPi / ZimaBoard / x86 mini PC
- Custom Debian-based SBCs

Install via custom scripts or build a bootable image. A YAML-based configuration system defines your network interfaces, startup behavior, and any tunnel setup.

---

## 🌐 Local API

Sentinel exposes endpoints for:
- Device status
- TTL-based access requests
- Internal health and monitoring
- Instance registration and schema-based contract sharing

> This allows custom nodes (AI inference, file servers, etc.) to announce themselves and expose UIs or APIs back to Sentinel.

---

## 🛠 Admin Philosophy

Sentinel is built for users who:
- Want **control without overhead**
- Don’t trust routers with limited UIs or poor security
- Prefer a instance-driven setup over traditional home lab models
- Value speed, clarity, and privacy — with zero reliance on third parties

---

## 🧪 Example Use Cases

- Home router replacement with full visibility
- Secure access point while traveling
- Distributed nodes across households or friends
- Local dashboard for self-hosted file servers, AI inference, or shared tunnels

---

## 📦 Getting Started

> Setup instructions, scripts, and YAML config templates coming soon.

---

**Project Sentinel**  
> Built for wireless-first, zero-trust, always-private networking.
