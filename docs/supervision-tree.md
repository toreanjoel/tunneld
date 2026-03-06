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
        WLAN[Wlan Server]
        ZROK[Zrok Server]
        SESS[Session Server]
        SRES[SystemResources]
        SVC[Services Server]
        RES[Resources Server]
        DEV[Devices Server]
        AUTH[Auth Server]
        BL[Blocklist Server]
        UPD[Updater Server]
        SQM[Sqm Server]
        CERT[CertManager]
    end

    subgraph Not Supervised - Called at Startup
        IPT[Iptables]
    end

    subgraph Plain Modules - No Process
        NGX[Nginx]
        DNSM[Dnsmasq]
        PERSIST[Persistence]
        CFG[Config]
    end

    RES --> NGX
    RES --> DNSM
    RES --> ZROK
    RES --> PERSIST
    AUTH --> PERSIST
    SQM --> PERSIST
    CERT --> NGX

    style EP fill:#7c3aed,color:#fff
    style PS fill:#7c3aed,color:#fff
    style RES fill:#ef4444,color:#fff
    style ZROK fill:#3b82f6,color:#fff
```

## Polling Intervals

| Server | Interval | What It Does |
|--------|----------|--------------|
| Session | 30s | Clean expired sessions |
| Devices | 10s | Read dnsmasq.leases, broadcast device list |
| Services | 10s | Check systemd service statuses |
| SystemResources | 10s | Read CPU, memory, disk via :os_mon |
| Resources | 10s | Broadcast resource list + health |
| Wlan | 15s | Check Wi-Fi connection status |
| Updater | 5min | Check GitHub for new version |
| CertManager | 6h | Check SSL cert expiry |

## PubSub Topics

```mermaid
graph LR
    subgraph GenServers
        DEV[Devices]
        SVC[Services]
        RES[Resources]
        SR[SystemResources]
        WLAN[Wlan]
        UPD[Updater]
        BL[Blocklist]
        ZROK[Zrok]
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
    end

    subgraph Dashboard LiveView
        DLV[Dashboard]
    end

    DEV --> CD --> DLV
    SVC --> CS --> DLV
    RES --> CR --> DLV
    SR --> CSR --> DLV
    WLAN --> CDT --> DLV
    WLAN --> SI --> DLV
    UPD --> CW --> DLV
    BL --> CDT
    ZROK --> CDT
    RES --> NT --> DLV

    style DLV fill:#7c3aed,color:#fff
```

The Dashboard subscribes to all topics and routes updates to child LiveComponents via `send_update/2`.
