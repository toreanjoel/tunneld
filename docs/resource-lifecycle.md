# Resource Lifecycle

How a local service goes from running on a device to being accessible publicly or privately through the overlay network.

## Creating a Resource

```mermaid
sequenceDiagram
    participant User as Dashboard
    participant Res as Resources Server
    participant FS as resources.json
    participant Nginx as Nginx
    participant DNS as Dnsmasq

    User->>Res: Add resource (name, ip, port, pool)
    Res->>Res: Validate pool entries (ip:port format)
    Res->>FS: Write resource to file
    Res->>Nginx: Generate reverse proxy config
    Res->>Nginx: Generate SSL cert (if needed)
    Res->>DNS: Add hairpin DNS entry
    Res-->>User: Resource created
```

## Enabling a Public Share

```mermaid
sequenceDiagram
    participant User as Dashboard
    participant Res as Resources Server
    participant Zrok as Zrok Server
    participant Sys as systemd

    User->>Res: Toggle public share ON
    Res->>Zrok: Reserve public endpoint (name, ip:port)
    Zrok->>Zrok: zrok reserve public
    Zrok->>Sys: Create systemd unit file
    Zrok->>Sys: Enable + start unit
    Zrok-->>Res: Reserved name returned
    Res->>Res: Store reserved name + unit info
    Res-->>User: Share enabled (accessible via name.share.zrok.io)
```

## Enabling a Private Share

```mermaid
sequenceDiagram
    participant User as Dashboard
    participant Res as Resources Server
    participant Zrok as Zrok Server
    participant Sys as systemd

    User->>Res: Toggle private share ON
    Res->>Zrok: Reserve private endpoint (name, ip:port)
    Zrok->>Zrok: zrok reserve private
    Zrok->>Sys: Create systemd unit file
    Zrok->>Sys: Enable + start unit
    Zrok-->>Res: Reserved name returned
    Res->>Res: Store reserved name + unit info
    Res-->>User: Share enabled (accessible via zrok access)
```

## Binding to a Remote Share (Access)

```mermaid
sequenceDiagram
    participant User as Dashboard
    participant Res as Resources Server
    participant Zrok as Zrok Server
    participant Nginx as Nginx
    participant DNS as Dnsmasq

    User->>Res: Add private resource (remote share name)
    Res->>Zrok: Bind access to share (allocates local port)
    Zrok->>Zrok: zrok access private (systemd unit)
    Zrok-->>Res: Local bind port returned
    Res->>Nginx: Generate proxy config (local port -> resource)
    Res->>DNS: Add hairpin DNS entry
    Res-->>User: Remote resource available locally via https://name.tunneld.sh
```
