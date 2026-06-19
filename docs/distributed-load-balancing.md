# Distributed Load Balancing

How Tunneld distributes traffic across local backends using nginx upstream pools.

## Overview

Each resource has a **pool** - a list of `ip:port` backends on the subnet
(e.g., `192.168.50.10:8080`). Nginx load balances across all pool entries for
the resource.

```mermaid
graph LR
    subgraph Client Request
        C[Client Device]
    end

    subgraph Tunneld Gateway
        DNS[dnsmasq Resolver]
        NG[nginx upstream pool]
    end

    subgraph Pool Backends
        L1[Local: 192.168.50.10:8080]
        L2[Local: 192.168.50.11:8080]
        L3[Local: 192.168.50.12:8080]
    end

    C -->|http://myapp.tunneld.lan:18000| DNS
    DNS -->|resolve to gateway IP| NG
    NG --> L1
    NG --> L2
    NG --> L3

    style NG fill:#7c3aed,color:#fff
    style L1 fill:#10b981,color:#fff
    style L2 fill:#10b981,color:#fff
    style L3 fill:#10b981,color:#fff
```

## How It Works

1. **Resource created** with a pool of backends (`ip:port` entries)
2. **Nginx config generated** with an `upstream` block listing all pool members,
   listening on `0.0.0.0:18000` with `server_name <name>.tunneld.lan`
3. **Health checking** - the Resources server periodically probes each backend via TCP
4. **DNS resolution** - dnsmasq resolves `<name>.tunneld.lan` to the gateway IP
5. **Traffic distributed** across all pool members (round-robin via nginx default)

## Combining Backends Across the Subnet

A single resource can front multiple backend instances of the same service
running on different subnet devices. Adding a backend to the pool is just
appending another `IP:port` entry - nginx handles the rest.

```mermaid
sequenceDiagram
    participant User as Dashboard
    participant Res as Resources Server
    participant Nginx as Nginx
    participant B1 as Backend 1
    participant B2 as Backend 2

    User->>Res: Update resource pool: [10.0.0.10:8080, 10.0.0.11:8080]
    Res->>Nginx: Regenerate upstream block
    Nginx-->>Res: :ok
    Note over Nginx: Round-robin between B1 and B2
    Nginx->>B1: request 1
    Nginx->>B2: request 2
    Nginx->>B1: request 3
```

Remote backends (across the mesh/relay) are planned for a later phase; today
the pool is limited to backends reachable from the gateway itself.