# Supervision Tree & Process Architecture

Tunneld runs as an OTP application with a flat `one_for_one` supervision tree.

## Process Map

```mermaid
graph TD
    subgraph Tunneld.Supervisor - one_for_one
        TEL[Telemetry]
        DNS_C[DNSCluster]
        PS[Phoenix.PubSub]
        EP[TunneldWeb.Endpoint]
        SESS[Session Server]
        SRES[SystemResources]
        SVC[Services Server]
        RES[Resources Server]
        DEV[Devices Server]
        AUTH[Auth Server]
        DNS_CFG[DnsConfig]
        UPD[Updater Server]
        WG[Wireguard]
        GEO[Geolocation]
        MESH[Mesh Server]
    end

    subgraph Not Supervised - Called at Startup
        IPT[Iptables]
    end

    subgraph Plain Modules - No Process
        NGX[Nginx]
        NETLINK[NetLink]
        PERSIST[Persistence]
        CFG[Config]
    end

    RES --> NGX
    RES --> PERSIST
    AUTH --> PERSIST
    MESH --> IPTABLES
    NETLINK -.reads.-> SYSFS[/sys/class/net/]

    style EP fill:#7c3aed,color:#fff
    style PS fill:#7c3aed,color:#fff
    style RES fill:#ef4444,color:#fff
    style MESH fill:#3b82f6,color:#fff
```

## Polling Intervals

| Server | Interval | What It Does |
|--------|----------|--------------|
| Session | 30s | Clean expired sessions |
| Devices | 10s | Read dnsmasq leases, broadcast device list |
| Services | 10s | Check systemd service statuses |
| SystemResources | 10s | Read CPU, memory, disk via :os_mon |
| Resources | 10s | Broadcast resource list + health |
| Mesh | 25s | Poll coordinator for peers, heartbeat, and mesh sync |
| Updater | 5min | Check GitHub for new version |

Link state for the upstream/downstream interfaces is read on demand from
`/sys/class/net/<iface>/operstate` by `Tunneld.NetLink` (no GenServer, no
polling) - the dashboard LiveView queries it directly.

## PubSub Topics

```mermaid
graph LR
    subgraph GenServers / Modules
        DEV[Devices]
        SVC[Services]
        RES[Resources]
        SR[SystemResources]
        UPD[Updater]
        DNS_CFG[DnsConfig]
        NETLINK[NetLink]
        MESH[Mesh]
    end

    subgraph PubSub Topics
        CD[component:devices]
        CS[component:services]
        CR[component:resources]
        CSR[component:system_resources]
        CDT[component:details]
        CW[component:welcome]
        SI[status:internet]
        NT[notifications]
        CM[component:mesh]
    end

    subgraph Dashboard LiveView
        DLV[Dashboard]
    end

    DEV --> CD --> DLV
    SVC --> CS --> DLV
    RES --> CR --> DLV
    SR --> CSR --> DLV
    UPD --> CW --> DLV
    DNS_CFG --> CDT
    NETLINK -.broadcast.-> SI --> DLV
    RES --> NT --> DLV
    MESH --> CM --> DLV

    style DLV fill:#7c3aed,color:#fff
```

The Dashboard subscribes to all topics and routes updates to child LiveComponents via `send_update/2`.