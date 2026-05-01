# Distributed Load Balancing

How Tunneld distributes traffic across local and remote backends using nginx upstream pools.

## Overview

Each resource has a **pool** — a list of `ip:port` backends. These can be:
- Local services on the subnet (e.g., `192.168.50.10:8080`)
- Remote services bound via Zrok access (e.g., `127.0.0.1:29182`)

Nginx load balances across all pool entries for the resource.

```mermaid
graph LR
    subgraph Client Request
        C[Client Device]
    end

    subgraph Tunneld Gateway
        DNS[DNS Resolver]
        NG[nginx upstream pool]
    end

    subgraph Pool Backends
        L1[Local: 192.168.50.10:8080]
        L2[Local: 192.168.50.11:8080]
        R1[Remote via Zrok: 127.0.0.1:29182]
    end

    C -->|https://myapp.tunneld.sh| DNS
    DNS -->|hairpin to gateway| NG
    NG --> L1
    NG --> L2
    NG --> R1

    style NG fill:#7c3aed,color:#fff
    style L1 fill:#10b981,color:#fff
    style L2 fill:#10b981,color:#fff
    style R1 fill:#3b82f6,color:#fff
```

## How It Works

1. **Resource created** with a pool of backends (`ip:port` entries)
2. **Nginx config generated** with an `upstream` block listing all pool members
3. **Health checking** — the Resources server periodically probes each backend via TCP
4. **DNS resolution** — dnsmasq resolves `resource.tunneld.sh` to the gateway IP
5. **SSL termination** — nginx handles TLS using a per-resource cert signed by the local Root CA
6. **Traffic distributed** across healthy backends

## Combining Local + Remote

```mermaid
sequenceDiagram
    participant A as Tunneld A (Host)
    participant Z as Zrok Overlay
    participant B as Tunneld B (Peer)

    Note over A: Has myapp running on local device
    A->>Z: zrok2 share private --share-token myapp-share
    Z-->>A: Share token: myapp-share

    Note over B: Wants to access myapp
    B->>Z: zrok2 access private myapp-share
    Z-->>B: Local port 29182

    Note over B: Add to pool alongside local backends
    B->>B: Pool: [192.168.50.5:8080, 127.0.0.1:29182]
    B->>B: Nginx load balances across both
```

This enables distributed deployments where the same service runs on multiple Tunneld networks, and each gateway balances across all instances — both local and remote.
