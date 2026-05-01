# Network Topology

How Tunneld bridges wireless upstream and wired downstream to form a private subnet.

```mermaid
graph TB
    subgraph Internet
        ISP[ISP / Upstream Router]
    end

    subgraph Tunneld Device
        WLAN[wlan0 - Wi-Fi Client]
        ETH[eth0 - Subnet Gateway]
        FW[iptables NAT + Forwarding]
        DHCP[dnsmasq - DHCP Server]
        DNS[dnsmasq - DNS Forwarder]
        NGINX[nginx - Reverse Proxy]
        APP[Tunneld - Phoenix LiveView]
    end

    subgraph Private Subnet
        D1[Device A]
        D2[Device B]
        D3[Device C]
    end

    ISP -->|Wi-Fi| WLAN
    WLAN --> FW
    FW --> ETH
    ETH --> D1
    ETH --> D2
    ETH --> D3
    D1 -->|DHCP Request| DHCP
    D2 -->|DHCP Request| DHCP
    D3 -->|DHCP Request| DHCP
    D1 -->|DNS Query| DNS
    D2 -->|DNS Query| DNS
    D3 -->|DNS Query| DNS
    DNS -->|Forward to User-Configured Server| ISP
    APP --> NGINX
    APP --> DHCP
    APP --> FW

    style WLAN fill:#7c3aed,color:#fff
    style ETH fill:#7c3aed,color:#fff
    style FW fill:#374151,color:#fff
    style DHCP fill:#374151,color:#fff
    style DNS fill:#374151,color:#fff
    style NGINX fill:#374151,color:#fff
    style APP fill:#7c3aed,color:#fff
```

## Data Flow

1. **Upstream**: Tunneld connects to the internet via Wi-Fi (`wlan0`)
2. **Downstream**: Devices plug into the ethernet port (`eth0`) and receive IPs via DHCP
3. **NAT**: iptables forwards traffic from eth0 through wlan0 with masquerading
4. **DNS**: All DNS queries are intercepted via iptables and routed through dnsmasq to the user-configured upstream DNS server
5. **Management**: The Phoenix LiveView dashboard controls all components
