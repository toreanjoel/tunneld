# Resource Lifecycle

How a local service on a subnet device becomes reachable from anywhere on the
subnet via a local DNS name and an nginx reverse proxy.

## Creating a Resource

```mermaid
sequenceDiagram
    participant User as Dashboard / Quick Expose
    participant Res as Resources Server
    participant FS as resources.json
    participant Nginx as Nginx

    User->>Res: Add resource (name, pool, description)
    Res->>Res: Validate pool entries (ip:port format)
    Res->>Res: Reject if name already exists
    Res->>Nginx: Generate reverse proxy config (server_name <name>.tunneld.lan)
    Nginx-->>Res: :ok
    Res->>FS: Write resource to file
    Res-->>User: Resource created (lan_url: http://<name>.tunneld.lan:18000)
```

A resource has:

- A **name** - used as the local DNS hostname (`<name>.tunneld.lan`)
- A **pool** - one or more `IP:port` backend entries load-balanced by nginx
- A **lan_url** - `http://<name>.tunneld.lan:18000`, reachable from any subnet
  device (dnsmasq resolves the name to the gateway IP)

There is no public-internet exposure and no per-resource auth. Access is
limited to the local subnet; relay/mesh exposure is future work.

## Updating a Resource

```mermaid
sequenceDiagram
    participant User as Dashboard
    participant Res as Resources Server
    participant FS as resources.json
    participant Nginx as Nginx

    User->>Res: Update resource (description, pool)
    Res->>Res: Find resource by id
    Res->>Res: Validate + normalize pool
    Res->>Nginx: Regenerate reverse proxy config
    Nginx-->>Res: :ok
    Res->>FS: Persist updated resource
    Res-->>User: Resource updated
```

Only host resources can be edited. The name is immutable after creation (it is
the DNS hostname); description and pool can be changed.

## Removing a Resource

```mermaid
sequenceDiagram
    participant User as Dashboard / Quick Expose
    participant Res as Resources Server
    participant FS as resources.json
    participant Nginx as Nginx

    User->>Res: Remove resource (id)
    Res->>Nginx: Remove sites-available/sites-enabled config
    Nginx-->>Res: :ok
    Res->>FS: Remove resource from file
    Res-->>User: Resource removed
```

Removing a resource deletes its nginx config and the persisted entry. Backend
services themselves are untouched.

## Health Checks

The Resources server runs a 10s sync that, for each host resource, performs a
short TCP connect against each pool entry and broadcasts the result:

- `:all_up`   - every backend accepted the connection
- `:partial`  - some backends up, some down
- `:none`     - no backends reachable
- `:empty`    - pool has no entries

In mock mode (`MOCK_DATA=true`) health is simulated: all but the first entry
are reported up.